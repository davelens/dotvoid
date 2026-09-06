# Managing services with runit on Void Linux

Void Linux uses **runit** instead of systemd. Manage enabled services with `sv`:

```bash
# Restart a service
sudo sv restart <service>

# Examples
sudo sv restart sshd
sudo sv restart NetworkManager
```

Other common commands:

```bash
sudo sv status <service>   # Check status
sudo sv up <service>       # Start
sudo sv down <service>     # Stop
```

Enable a service immediately and at boot:

```bash
sudo ln -s /etc/sv/<service> /var/service/
```

Disable a service:

```bash
sudo rm /var/service/<service>
```

List the status of all enabled services:

```bash
sudo sv status /var/service/*
```

Service definitions are stored in `/etc/sv/`; enabled services appear in `/var/service/`.
