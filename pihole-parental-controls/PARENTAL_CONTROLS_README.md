# Pi-hole Parental Controls

A comprehensive parental control extension for Pi-hole that allows you to block specific services (YouTube, Minecraft, PlayStation Network, social media, etc.), manage device access, set time limits, and schedule blocking periods.

## Features

- **Service-Based Blocking**: Block specific services like:
  - YouTube
  - Gaming platforms (Minecraft, PSN, Xbox Live, Steam, Epic Games)
  - Social media (Facebook, Instagram, Twitter/X, TikTok, Snapchat)
  - Streaming services (Netflix, Hulu, Disney+, Prime Video)
  - Messaging apps (WhatsApp, Telegram, Discord)
  - Shopping sites (Amazon, eBay)
  - Adult content
  - And more...

- **Device & Group Targeting**: Apply rules to:
  - Individual devices
  - Groups of devices
  - All devices on the network

- **Time-Based Controls**:
  - Schedule blocking for specific times (e.g., bedtime, school hours)
  - Set daily, weekly, or one-time schedules
  - Support for recurring schedules

- **Time Limits**:
  - Daily usage limits (e.g., 2 hours per day)
  - Weekly limits
  - Automatic enforcement

- **Flexible Rules**:
  - Multiple rules with different priorities
  - Combine services, targets, schedules, and limits
  - Enable/disable rules on demand

## Installation

### Prerequisites

- Pi-hole must be already installed and running
- Root access to the Pi-hole server
- SQLite3 (usually included with Pi-hole)

### Install Parental Controls

1. Clone or download the Pi-hole Parental Controls fork:
   ```bash
   git clone https://github.com/yourusername/pihole-parental-controls.git
   cd pihole-parental-controls
   ```

2. Run the setup script:
   ```bash
   sudo bash advanced/Scripts/parental-setup.sh install
   ```

3. Verify the installation:
   ```bash
   pihole parental scheduler status
   ```

The setup script will:
- Apply database schema changes
- Add default service categories
- Install and start the scheduler daemon
- Configure systemd service for automatic startup

## Quick Start

### 1. View Available Services

```bash
pihole parental service list
```

This shows pre-configured service categories like YouTube, Gaming, Social Media, etc.

### 2. Add Domains to Services

The user will provide comprehensive domain lists. To add them:

```bash
# Add a single domain
pihole parental service domain add 1 example.com

# Import domains from a file
pihole parental service import 1 /path/to/youtube-domains.txt

# Add a regex domain pattern
pihole parental service domain add 1 '.*youtube.*' --regex
```

### 3. Create a Parental Control Rule

```bash
# Create a rule
pihole parental rule add "Bedtime YouTube Block" "Block YouTube during bedtime"

# Attach YouTube service to the rule (assuming rule ID is 1)
pihole parental rule attach service 1 1 block

# Target a specific device (assuming device ID is 5)
pihole parental rule attach target 1 device 5

# Or target all devices
pihole parental rule attach target 1 all

# Add a schedule (block from 8 PM to 7 AM daily)
pihole parental rule schedule 1 daily 20:00 07:00

# Set a time limit (2 hours per day)
pihole parental rule limit 1 daily 120

# Enable the rule
pihole parental rule enable 1
```

### 4. View Rules

```bash
# List all rules
pihole parental rule list

# Show detailed information about a rule
pihole parental rule show 1
```

## Usage Examples

### Example 1: Block Gaming During School Hours

```bash
# Create rule
pihole parental rule add "School Hours Gaming Block"

# Attach gaming service (ID: 2)
pihole parental rule attach service 1 2 block

# Target child's device (assume ID: 10)
pihole parental rule attach target 1 device 10

# Schedule: Monday-Friday, 8 AM to 3 PM
pihole parental rule schedule 1 weekly 08:00 15:00 "[1,2,3,4,5]"

# Enable
pihole parental rule enable 1
```

### Example 2: Limit Social Media to 1 Hour Per Day

```bash
# Create rule
pihole parental rule add "Social Media Time Limit"

# Attach social media service (ID: 3)
pihole parental rule attach service 2 3 block

# Target teenager's device (ID: 11)
pihole parental rule attach target 2 device 11

# Set daily limit: 60 minutes
pihole parental rule limit 2 daily 60

# Always active (no schedule means always on)
pihole parental rule enable 2
```

### Example 3: Complete Internet Block During Bedtime

```bash
# Create rule
pihole parental rule add "Bedtime Internet Block"

# Attach all services (or create a special "All Internet" service)
# For now, attach multiple services
pihole parental rule attach service 3 1 block  # YouTube
pihole parental rule attach service 3 2 block  # Gaming
pihole parental rule attach service 3 3 block  # Social Media
# ... attach more services as needed

# Target all children's devices
pihole parental rule attach target 3 group 5  # Assuming group 5 is "Children"

# Schedule: Daily 9 PM to 6 AM
pihole parental rule schedule 3 daily 21:00 06:00

# Enable
pihole parental rule enable 3
```

### Example 4: Block Specific Service on Weekends

```bash
# Create rule
pihole parental rule add "Weekend YouTube Block"

# Attach YouTube
pihole parental rule attach service 4 1 block

# Target specific device
pihole parental rule attach target 4 device 12

# Schedule: Saturday and Sunday, all day
pihole parental rule schedule 4 weekly 00:00 23:59 "[0,6]"

# Enable
pihole parental rule enable 4
```

## Command Reference

### Service Management

```bash
# List all service categories
pihole parental service list

# Add a new service category
pihole parental service add <name> [description]

# Remove a service category
pihole parental service remove <id>

# Enable/disable a service
pihole parental service enable <id>
pihole parental service disable <id>

# List domains for a service
pihole parental service domains <service_id>

# Add domain to service
pihole parental service domain add <service_id> <domain> [--regex]

# Remove domain from service
pihole parental service domain remove <domain_id>

# Import domains from file
pihole parental service import <service_id> <file> [--regex]
```

### Rule Management

```bash
# List all rules
pihole parental rule list

# Add a new rule
pihole parental rule add <name> [description] [priority]

# Remove a rule
pihole parental rule remove <id>

# Enable/disable a rule
pihole parental rule enable <id>
pihole parental rule disable <id>

# Show rule details
pihole parental rule show <id>

# Attach service to rule
pihole parental rule attach service <rule_id> <service_id> [block|allow]

# Detach service from rule
pihole parental rule detach service <rule_id> <service_id>

# Attach target to rule
pihole parental rule attach target <rule_id> <all|group|device> [id]

# Add schedule to rule
pihole parental rule schedule <rule_id> <daily|weekly|once|always> <start_time> <end_time> [days]

# Set time limit
pihole parental rule limit <rule_id> <daily|weekly|monthly> <minutes>

# Manually apply/unapply rule
pihole parental rule apply <rule_id>
pihole parental rule unapply <rule_id>
```

### Scheduler Management

```bash
# Check scheduler status
pihole parental scheduler status

# Start scheduler
pihole parental scheduler start

# Stop scheduler
pihole parental scheduler stop

# Restart scheduler
pihole parental scheduler restart
```

## Schedule Format

Schedules use 24-hour time format (HH:MM).

### Schedule Types

- **daily**: Active every day at specified times
- **weekly**: Active on specific days of the week
  - Days format: `"[0,1,2,3,4,5,6]"` where 0=Sunday, 6=Saturday
  - Example: `"[1,2,3,4,5]"` = Monday through Friday
- **once**: Active on a specific date
- **always**: Always active (no time restrictions)

### Time Ranges

- **Same-day range**: `09:00 17:00` (9 AM to 5 PM)
- **Overnight range**: `20:00 07:00` (8 PM to 7 AM next day)

## Device & Group IDs

To find device and group IDs:

```bash
# List clients
sqlite3 /etc/pihole/gravity.db "SELECT id, ip, comment FROM client"

# List groups
sqlite3 /etc/pihole/gravity.db "SELECT id, name, description FROM 'group'"
```

Or use Pi-hole's web interface to manage clients and groups.

## Architecture

The parental controls system consists of:

1. **Database Schema**: Extended Pi-hole's SQLite database with new tables
2. **Service Management**: Scripts to manage service categories and domains
3. **Rule Management**: Scripts to create and configure rules
4. **Scheduler Daemon**: Background service that enforces time-based controls
5. **CLI Integration**: Commands integrated into the main `pihole` command

### How It Works

1. You define **services** with lists of domains
2. You create **rules** that specify:
   - Which services to block
   - Which devices/groups to target
   - When to block (schedules)
   - Usage limits (time limits)
3. The **scheduler daemon** runs every minute and:
   - Checks if schedules are active
   - Applies blocking by adding domains to Pi-hole's blocklist
   - Removes blocking when schedules end
   - Tracks usage and enforces limits

## Logs

Scheduler logs are stored in:
```
/var/log/pihole/parental-scheduler.log
```

View logs:
```bash
tail -f /var/log/pihole/parental-scheduler.log
```

## Troubleshooting

### Scheduler Not Running

```bash
# Check status
systemctl status pihole-parental-scheduler

# View logs
journalctl -u pihole-parental-scheduler -n 50

# Restart
sudo systemctl restart pihole-parental-scheduler
```

### Rules Not Blocking

1. Verify rule is enabled:
   ```bash
   pihole parental rule show <rule_id>
   ```

2. Check if schedule is active (if scheduled)

3. Verify domains are in the blocklist:
   ```bash
   pihole -q youtube.com
   ```

4. Check Pi-hole FTL logs:
   ```bash
   pihole -t
   ```

### Database Issues

Run Pi-hole's repair:
```bash
pihole -r
```

## Uninstallation

To remove parental controls:

```bash
sudo bash advanced/Scripts/parental-setup.sh uninstall
```

This will:
- Stop and remove the scheduler service
- Preserve database tables (can be manually removed if needed)

## Domain Lists

The user will provide comprehensive domain lists for all services. Once provided, import them using:

```bash
# YouTube domains
pihole parental service import 1 youtube-domains.txt

# Gaming domains
pihole parental service import 2 gaming-domains.txt

# Social media domains
pihole parental service import 3 social-media-domains.txt

# And so on...
```

Domain list files should have one domain per line, with optional comments starting with `#`.

## Security Notes

1. **Authentication**: Parental controls use Pi-hole's existing authentication
2. **Bypass Prevention**: Consider blocking:
   - DNS over HTTPS (DoH) providers
   - VPN services
   - Proxy services
   - Alternative DNS servers
3. **Physical Access**: Users with physical access to the Pi-hole can disable controls
4. **Router-Level**: For maximum security, implement controls at the router level

## Contributing

Contributions are welcome! Areas for improvement:

- Web UI for easier management
- More sophisticated usage tracking
- Mobile app integration
- Real-time notifications
- Advanced scheduling (school calendar integration)
- Whitelist management per rule

## License

This project extends Pi-hole and is licensed under the EUPL (European Union Public License).

## Support

For issues and questions:
- Check the troubleshooting section
- Review Pi-hole documentation: https://docs.pi-hole.net
- Open an issue on GitHub

## Credits

Based on Pi-hole by Pi-hole LLC (https://pi-hole.net)
Parental Controls extension by [Your Name/Organization]
