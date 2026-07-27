#define _POSIX_C_SOURCE 200809L

#include "ext-data-control-v1-client-protocol.h"

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

struct clipboard_state {
    struct wl_display *display;
    struct ext_data_control_manager_v1 *manager;
    struct ext_data_control_device_v1 *device;
    struct ext_data_control_source_v1 *source;
    struct wl_seat *seat;
    const char *image_path;
    bool running;
};

static bool write_all(int fd, const void *buffer, size_t length)
{
    const char *cursor = buffer;
    while (length > 0) {
        ssize_t written = write(fd, cursor, length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        cursor += written;
        length -= (size_t)written;
    }
    return true;
}

static void send_file(int output_fd, const char *path)
{
    int input_fd = open(path, O_RDONLY | O_CLOEXEC);
    if (input_fd < 0) {
        return;
    }

    char buffer[65536];
    for (;;) {
        ssize_t count = read(input_fd, buffer, sizeof(buffer));
        if (count == 0) {
            break;
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (!write_all(output_fd, buffer, (size_t)count)) {
            break;
        }
    }
    close(input_fd);
}

static void source_send(
    void *data,
    struct ext_data_control_source_v1 *source,
    const char *mime_type,
    int32_t fd)
{
    (void)source;
    struct clipboard_state *state = data;

    if (strcmp(mime_type, "image/png") == 0) {
        send_file(fd, state->image_path);
    } else {
        write_all(fd, state->image_path, strlen(state->image_path));
    }
    close(fd);
}

static void source_cancelled(
    void *data,
    struct ext_data_control_source_v1 *source)
{
    (void)source;
    struct clipboard_state *state = data;
    state->running = false;
}

static const struct ext_data_control_source_v1_listener source_listener = {
    .send = source_send,
    .cancelled = source_cancelled,
};

static void offer_mime(
    void *data,
    struct ext_data_control_offer_v1 *offer,
    const char *mime_type)
{
    (void)data;
    (void)offer;
    (void)mime_type;
}

static const struct ext_data_control_offer_v1_listener offer_listener = {
    .offer = offer_mime,
};

static void device_data_offer(
    void *data,
    struct ext_data_control_device_v1 *device,
    struct ext_data_control_offer_v1 *offer)
{
    (void)data;
    (void)device;
    ext_data_control_offer_v1_add_listener(offer, &offer_listener, NULL);
}

static void destroy_offer(struct ext_data_control_offer_v1 *offer)
{
    if (offer != NULL) {
        ext_data_control_offer_v1_destroy(offer);
    }
}

static void device_selection(
    void *data,
    struct ext_data_control_device_v1 *device,
    struct ext_data_control_offer_v1 *offer)
{
    (void)data;
    (void)device;
    destroy_offer(offer);
}

static void device_finished(
    void *data,
    struct ext_data_control_device_v1 *device)
{
    (void)device;
    struct clipboard_state *state = data;
    state->running = false;
}

static void device_primary_selection(
    void *data,
    struct ext_data_control_device_v1 *device,
    struct ext_data_control_offer_v1 *offer)
{
    (void)data;
    (void)device;
    destroy_offer(offer);
}

static const struct ext_data_control_device_v1_listener device_listener = {
    .data_offer = device_data_offer,
    .selection = device_selection,
    .finished = device_finished,
    .primary_selection = device_primary_selection,
};

static void seat_capabilities(
    void *data,
    struct wl_seat *seat,
    enum wl_seat_capability capabilities)
{
    (void)data;
    (void)seat;
    (void)capabilities;
}

static void seat_name(void *data, struct wl_seat *seat, const char *name)
{
    (void)data;
    (void)seat;
    (void)name;
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

static void registry_global(
    void *data,
    struct wl_registry *registry,
    uint32_t name,
    const char *interface,
    uint32_t version)
{
    struct clipboard_state *state = data;

    if (strcmp(interface, ext_data_control_manager_v1_interface.name) == 0) {
        state->manager = wl_registry_bind(
            registry,
            name,
            &ext_data_control_manager_v1_interface,
            version < 1 ? version : 1);
    } else if (state->seat == NULL && strcmp(interface, wl_seat_interface.name) == 0) {
        state->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
        wl_seat_add_listener(state->seat, &seat_listener, state);
    }
}

static void registry_global_remove(
    void *data,
    struct wl_registry *registry,
    uint32_t name)
{
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

int main(int argc, char **argv)
{
    if (argc != 2 || argv[1][0] != '/') {
        fprintf(stderr, "usage: %s /absolute/path/to/image.png\n", argv[0]);
        return 2;
    }

    signal(SIGPIPE, SIG_IGN);

    struct clipboard_state state = {
        .image_path = argv[1],
        .running = true,
    };

    state.display = wl_display_connect(NULL);
    if (state.display == NULL) {
        fprintf(stderr, "unable to connect to the Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(state.display);
    wl_registry_add_listener(registry, &registry_listener, &state);
    if (wl_display_roundtrip(state.display) < 0 || state.manager == NULL || state.seat == NULL) {
        fprintf(stderr, "ext-data-control or Wayland seat is unavailable\n");
        return 1;
    }

    state.device = ext_data_control_manager_v1_get_data_device(state.manager, state.seat);
    ext_data_control_device_v1_add_listener(state.device, &device_listener, &state);

    state.source = ext_data_control_manager_v1_create_data_source(state.manager);
    ext_data_control_source_v1_add_listener(state.source, &source_listener, &state);
    ext_data_control_source_v1_offer(state.source, "image/png");
    ext_data_control_source_v1_offer(state.source, "text/plain");
    ext_data_control_source_v1_offer(state.source, "text/plain;charset=utf-8");
    ext_data_control_source_v1_offer(state.source, "UTF8_STRING");
    ext_data_control_source_v1_offer(state.source, "TEXT");
    ext_data_control_source_v1_offer(state.source, "STRING");
    ext_data_control_device_v1_set_selection(state.device, state.source);
    wl_display_flush(state.display);

    while (state.running && wl_display_dispatch(state.display) >= 0) {
    }

    wl_display_disconnect(state.display);
    return 0;
}
