# Pi-hole + Unbound Docker Installer & Manager

This is a comprehensive, menu-driven Bash script designed to provide a production-ready, secure, and easy-to-manage installation of Pi-hole with its own Unbound recursive DNS resolver, all running within a Docker container.

The script automates the entire setup process, from host preparation to container deployment and post-install verification. It also provides a powerful management menu for routine tasks like updating, backups, and configuration changes.

## ✨ Key Features

-   **All-in-One Solution**: Installs Pi-hole and a pre-configured Unbound resolver for enhanced privacy and security.
-   **Menu-Driven Interface**: Simplifies both initial installation and ongoing management. No complex commands to memorize.
-   **Automated Host Preparation**: Automatically detects and disables `systemd-resolved` to free up port 53.
-   **Production-Ready Configuration**: Creates a robust `docker-compose.yml` with health checks, persistent volumes, and secure settings.
-   **Curated Adlists**: Comes with a strong, built-in set of default adlists to provide excellent block rates out of the box.
-   **Bulk Import/Export**: Easily import and export your custom adlists and domain rules (allow/deny lists) from simple text files.
-   **Comprehensive Management**: The post-install menu includes tools to:
    -   Update the container to the latest version.
    -   View status and run diagnostics.
    -   Change the admin password.
    -   View and follow logs.
    -   Fix volume permissions.
    -   Set up an automated permission-fixing cron job.
    -   Test DNSSEC validation.
-   **Clean Uninstall**: A dedicated menu option to completely and cleanly remove the container, its volumes, and all configuration files created by the script.

## 📋 Prerequisites

Before running the script, ensure your system meets the following requirements:

-   A Linux-based OS (tested on Debian/Ubuntu).
-   `sudo` or root privileges.
-   **Docker** and **Docker Compose** installed and running.
-   The following command-line tools: `curl`, `dig`, `systemctl`, and `jq`. The script will check for these and exit if they are not found.

## 🚀 Installation & Usage

1.  **Download the script:**
    ```bash
    curl -O https://path/to/your/script/install.sh
    # Or wget
    # wget https://path/to/your/script/install.sh
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x install.sh
    ```

3.  **Run the script:**
    ```bash
    sudo ./install.sh
    ```
    > **Note**: Running with `sudo` is recommended as the script needs to manage Docker, create directories, and potentially modify system services like `systemd-resolved`.

4.  **Follow the Menu:**
    -   On the first run, you will be presented with the **Installation Menu**.
    -   Choose `1. Fresh Installation` for a quick setup with sensible defaults.
    -   Choose `2. Custom Installation` to configure the Web UI port, admin password, and timezone.
    -   The script will guide you through a confirmation step before making any changes.

## 🔧 Management Menu Explained

Once the installation is complete, running the script again (`sudo ./install.sh`) will bring you to the main **Management Menu**:

| Option | Description                                                                                                 |
| :----- | :-----------------------------------------------------------------------------------------------------------|
| **1**  | **Fresh Installation**: Destroys the current setup (container, volumes, configs) and starts over.           |
| **2**  | **Update Container**: Pulls the latest `mpgirro/pihole-unbound` image and recreates the container.          |
| **3**  | **View Status & Diagnostics**: Shows `docker compose ps` output, container health, and runs DNS tests.      |
| **4**  | **Reinstall/Repair**: Re-runs the entire installation sequence, useful for repairing a broken setup.        |
| **5**  | **Fix Permissions**: Corrects file ownership on the host volumes and within the container.                  |
| **6**  | **Setup Auto Permission Fixer**: Installs an hourly cron job to automatically fix internal permissions.     |
| **7**  | **Change Pi-hole Password**: Securely change the web admin password for Pi-hole.                            |
| **8**  | **Import Adlists from File**: Bulk-adds adlists from a file named `adlists.txt` (or a custom name).         |
| **9**  | **Import Domain Rules from Script**: Bulk-adds domain/regex rules from a file `domains.txt`.                |
| **10** | **Set Custom NTP Server**: Change the time synchronization server used by the container's FTL service.      |
| **11** | **Export Domain Rules to Script**: Backs up your domain/regex rules to `domains-backup.sh`.                 |
| **12** | **Export Adlists to File**: Backs up your adlist URLs and comments to `adlists-backup.txt`.                 |
| **13** | **Test DNSSEC Validation**: Performs a quick test to ensure Unbound is correctly validating DNSSEC.         |
| **14** | **View Pi-hole Logs**: Shows the last 50 log lines and then follows the live container logs.                |
| **15** | **Uninstall Pi-hole**: Completely removes the container, volumes, networks, and all script-generated files. |
| **16** | **Exit**: Exits the script.                                                                                 |

---

## 📁 File Structure

The script creates the following files and directories in the same location where it is run:

```
.
├── adlists-backup.txt         # (Optional) Created by the adlist export function.
├── adlists-example.txt        # An example file for the adlist import format.
├── adlists.txt                # (Optional) User-created file for importing custom adlists.
├── domains-backup.sh          # (Optional) Created by the domain export function.
├── domains-example.txt        # An example file for the domain import format.
├── domains.txt                # (Optional) User-created file for importing domain rules.
├── docker-compose.yml         # The main Docker Compose configuration file.
├── etc-dnsmasq.d/             # Persistent storage for custom dnsmasq configurations.
├── etc-pihole/                # Persistent storage for Pi-hole's database and core configs.
├── install.log                # A log file of all actions performed by the script.
├── install.sh                 # This script.
└── .env                       # Stores the secret WEBPASSWORD for the container.
```

## ⚙️ Bulk Import File Formats

### Adlist Import (`adlists.txt`)

Create a file named `adlists.txt`. Each line should contain the URL, a pipe character (`|`), and a comment. Lines starting with `#` are ignored.

**Format:** `https://path/to/list.txt|A comment for this list`

**Example `adlists.txt`:**
```
# My Favorite Adlists
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt|Hagezi Pro
https://some.other.list/hosts.txt|My custom adlist
```

### Domain Rule Import (`domains.txt`)

Create a file named `domains.txt`. Rules are defined in blocks of key-value pairs, separated by blank lines.

**Supported Keys:**
-   `domain`: The domain name or regex pattern.
-   `type`: Must be one of `exact-allow`, `exact-deny`, `regex-allow`, or `regex-deny`.
-   `comment`: (Optional) A description for the rule.
-   `groups`: (Optional) A comma-separated list of Pi-hole groups to apply the rule to (e.g., `Default,Kids`).

**Example `domains.txt`:**
```
# Allow a necessary service
domain: (\.|^)good-service\.com$
type:   regex-allow
comment: Allow this essential service for streaming
groups: Default

# Block a known tracker
domain: bad-tracker.com
type:   exact-deny
comment: A known ad server
groups: Default,Marketing
```

## ⚠️ Security Warning

This script configures Pi-hole to listen on all interfaces. This is standard for a Docker setup and is secure as long as **your host machine's firewall does not expose port 53 (TCP/UDP) to the public internet**. Ensure your firewall rules are correctly configured to only allow DNS requests from your local network.

## 💡 Troubleshooting

-   **"Port 53 already in use"**: This usually means another DNS service (like `dnsmasq`) is running. The script tries to handle `systemd-resolved`, but if another service is the cause, you must stop and disable it manually.
-   **"Container is unhealthy" or Fails to Start**: Run menu option `14. View Pi-hole Logs` or use the command `docker logs pihole` to inspect the container's output for specific errors.
-   **Permission Errors**: If you encounter issues with gravity updates or saving settings, use menu option `5. Fix Permissions & Config`.
