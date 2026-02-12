# OpenVPN client config (encrypted)

This dotfiles repo manages the OpenVPN client config at `/etc/openvpn/client/client.conf` using **age** encryption via chezmoi. The file is stored in the repo as `etc/openvpn/client/encrypted_client.conf.age` and is decrypted on apply.

## Encryption (age)

- **Identity** (decrypt): `~/.config/chezmoi/age.txt` — you already have this.
- **Recipient** (encrypt): needed for `chezmoi add --encrypt`. Get it with:
  ```bash
  age-keygen -y < ~/.config/chezmoi/age.txt
  ```
  Add that line as `recipient = "age1..."` under `[age]` in `~/.config/chezmoi/chezmoi.toml` so you can add or re-encrypt files.

Chezmoi decrypts automatically when you run `apply`, `diff`, or `edit`; no manual decrypt step.

## First-time: add your config to the repo

With `sudo`, chezmoi uses `/root` as destination, so `chezmoi add /etc/...` fails. Create the encrypted file manually from the **repo root** (as your normal user):

1. Ensure you have the age recipient in config (see [Encryption](#encryption-age)); get it with `age-keygen -y < ~/.config/chezmoi/age.txt`.
2. Create the encrypted file from your **dotfiles repo root** (sudo only to read the config; the redirect runs as you so the file lands in the repo):
   ```bash
   cd ~/Repos/dotfiles   # or your actual repo path
   sudo cat /etc/openvpn/client/client.conf | age -e -r "$(age-keygen -y < ~/.config/chezmoi/age.txt)" > etc/openvpn/client/encrypted_client.conf.age
   ```
3. Commit the new encrypted file:
   ```bash
   git add etc/openvpn/client/encrypted_client.conf.age
   git commit -m "Add encrypted OpenVPN client.conf"
   ```

## Updating the config

Edit the decrypted content; chezmoi will re-encrypt when you save:

```bash
sudo chezmoi edit /etc/openvpn/client/client.conf
```

Then re-apply and restart the VPN:

```bash
sudo chezmoi apply
sudo systemctl restart openvpn-client@client
```

## Deploy (apply)

From the machine where you want the config:

```bash
sudo chezmoi apply
```

This decrypts the file to `/etc/openvpn/client/client.conf` and sets permissions (dir `750`, file `640`, owner `root:network`) so the `openvpn` user (group `network`) can read it.

## Restart VPN

After changing the config:

```bash
sudo systemctl restart openvpn-client@client
```

## Verify DNS integration

With the VPN up and the dns-up/dns-down scripts in use:

```bash
resolvectl status tun0
```

You should see the VPN DNS servers and split-DNS domains for the tunnel.

## No plaintext in the repo

Only the `.age` file is tracked. A plaintext `etc/openvpn/client/client.conf` in the source is ignored by `.chezmoiignore`. Never commit an unencrypted client config.
