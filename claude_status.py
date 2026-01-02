#!/usr/bin/env python3
"""
Claude Status Menu Bar App
A macOS menu bar app that displays Claude.ai usage statistics.
Designed with a liquid glass aesthetic for macOS Sonoma.
"""

import rumps
import subprocess
import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
import threading
import time
import requests

class ClaudeStatusApp(rumps.App):
    def __init__(self):
        super(ClaudeStatusApp, self).__init__(
            "Claude",
            icon=None,
            quit_button=None
        )

        # Usage data storage
        self.usage_data = {
            'session': {'used': 0, 'reset_time': 'Loading...'},
            'week_all': {'used': 0, 'reset_time': 'Loading...'},
            'week_sonnet': {'used': 0, 'reset_time': 'Loading...'},
            'extra_usage': False,
            'last_updated': None,
            'status': 'connecting'
        }

        # Cache for credentials
        self._credentials_cache = None
        self._credentials_cache_time = 0

        # Configure menu bar title with icon
        self.title = "◐ --"

        # Build the menu
        self.build_menu()

        # Start the update timer (every 1 second)
        self.timer = rumps.Timer(self.update_status, 1)
        self.timer.start()

        # Initial fetch
        self.fetch_usage_data()

    def build_menu(self):
        """Build the dropdown menu with liquid glass styling."""
        self.menu.clear()

        # Header
        header = rumps.MenuItem("━━━ Claude Usage Status ━━━")
        header.set_callback(None)
        self.menu.add(header)

        self.menu.add(rumps.separator)

        # Session usage (5-hour)
        self.session_item = rumps.MenuItem(
            f"◉ Current session: {self.usage_data['session']['used']}% used"
        )
        self.session_item.set_callback(None)
        self.menu.add(self.session_item)

        self.session_reset = rumps.MenuItem(
            f"   {self.usage_data['session']['reset_time']}"
        )
        self.session_reset.set_callback(None)
        self.menu.add(self.session_reset)

        self.menu.add(rumps.separator)

        # Week all models
        self.week_all_item = rumps.MenuItem(
            f"◉ Current week (all models): {self.usage_data['week_all']['used']}% used"
        )
        self.week_all_item.set_callback(None)
        self.menu.add(self.week_all_item)

        self.week_all_reset = rumps.MenuItem(
            f"   {self.usage_data['week_all']['reset_time']}"
        )
        self.week_all_reset.set_callback(None)
        self.menu.add(self.week_all_reset)

        self.menu.add(rumps.separator)

        # Week Sonnet only
        self.week_sonnet_item = rumps.MenuItem(
            f"◉ Current week (Sonnet only): {self.usage_data['week_sonnet']['used']}% used"
        )
        self.week_sonnet_item.set_callback(None)
        self.menu.add(self.week_sonnet_item)

        self.week_sonnet_reset = rumps.MenuItem(
            f"   {self.usage_data['week_sonnet']['reset_time']}"
        )
        self.week_sonnet_reset.set_callback(None)
        self.menu.add(self.week_sonnet_reset)

        self.menu.add(rumps.separator)

        # Extra usage
        extra_status = "Enabled" if self.usage_data['extra_usage'] else "Not enabled"
        self.extra_item = rumps.MenuItem(f"◎ Extra usage: {extra_status}")
        self.extra_item.set_callback(None)
        self.menu.add(self.extra_item)

        self.menu.add(rumps.separator)

        # Progress bars (visual representation)
        self.menu.add(rumps.MenuItem("━━━ Visual Progress ━━━"))
        self.progress_session = rumps.MenuItem(self.create_progress_bar("Session", self.usage_data['session']['used']))
        self.progress_session.set_callback(None)
        self.menu.add(self.progress_session)

        self.progress_week = rumps.MenuItem(self.create_progress_bar("Week", self.usage_data['week_all']['used']))
        self.progress_week.set_callback(None)
        self.menu.add(self.progress_week)

        self.progress_sonnet = rumps.MenuItem(self.create_progress_bar("Sonnet", self.usage_data['week_sonnet']['used']))
        self.progress_sonnet.set_callback(None)
        self.menu.add(self.progress_sonnet)

        self.menu.add(rumps.separator)

        # Last updated
        update_time = self.usage_data['last_updated'] or "Never"
        self.last_update_item = rumps.MenuItem(f"Updated: {update_time}")
        self.last_update_item.set_callback(None)
        self.menu.add(self.last_update_item)

        # Refresh button
        self.menu.add(rumps.MenuItem("↻ Refresh Now", callback=self.manual_refresh))

        self.menu.add(rumps.separator)

        # Quit button
        self.menu.add(rumps.MenuItem("Quit", callback=self.quit_app))

    def create_progress_bar(self, label, percentage):
        """Create a text-based progress bar."""
        filled = int(percentage / 5)  # 20 chars total
        empty = 20 - filled
        bar = "█" * filled + "░" * empty
        return f"{label}: [{bar}] {percentage}%"

    def get_status_icon(self):
        """Get status icon based on usage levels."""
        max_usage = max(
            self.usage_data['session']['used'],
            self.usage_data['week_all']['used'],
            self.usage_data['week_sonnet']['used']
        )

        if self.usage_data['status'] == 'connecting':
            return "◌"
        elif self.usage_data['status'] == 'error':
            return "◍"
        elif max_usage >= 90:
            return "◉"  # Critical - full circle
        elif max_usage >= 70:
            return "◕"  # High - mostly filled
        elif max_usage >= 50:
            return "◑"  # Medium - half filled
        elif max_usage >= 25:
            return "◔"  # Low - quarter filled
        else:
            return "○"  # Very low - empty circle

    def update_menu_display(self):
        """Update all menu items with current data."""
        # Update menu bar title
        max_usage = max(
            self.usage_data['session']['used'],
            self.usage_data['week_all']['used'],
            self.usage_data['week_sonnet']['used']
        )
        icon = self.get_status_icon()
        self.title = f"{icon} {max_usage}%"

        # Update menu items
        if hasattr(self, 'session_item'):
            self.session_item.title = f"◉ Current session: {self.usage_data['session']['used']}% used"
            self.session_reset.title = f"   {self.usage_data['session']['reset_time']}"

            self.week_all_item.title = f"◉ Current week (all models): {self.usage_data['week_all']['used']}% used"
            self.week_all_reset.title = f"   {self.usage_data['week_all']['reset_time']}"

            self.week_sonnet_item.title = f"◉ Current week (Sonnet only): {self.usage_data['week_sonnet']['used']}% used"
            self.week_sonnet_reset.title = f"   {self.usage_data['week_sonnet']['reset_time']}"

            extra_status = "Enabled" if self.usage_data['extra_usage'] else "Not enabled"
            self.extra_item.title = f"◎ Extra usage: {extra_status}"

            self.progress_session.title = self.create_progress_bar("Session", self.usage_data['session']['used'])
            self.progress_week.title = self.create_progress_bar("Week", self.usage_data['week_all']['used'])
            self.progress_sonnet.title = self.create_progress_bar("Sonnet", self.usage_data['week_sonnet']['used'])

            update_time = self.usage_data['last_updated'] or "Never"
            self.last_update_item.title = f"Updated: {update_time}"

    def get_credentials(self):
        """Get Claude Code credentials from macOS Keychain."""
        # Cache credentials for 5 minutes to avoid repeated keychain access
        current_time = time.time()
        if self._credentials_cache and (current_time - self._credentials_cache_time) < 300:
            return self._credentials_cache

        try:
            result = subprocess.run(
                ['security', 'find-generic-password', '-s', 'Claude Code-credentials', '-w'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                creds = json.loads(result.stdout.strip())
                self._credentials_cache = creds
                self._credentials_cache_time = current_time
                return creds
        except Exception as e:
            print(f"Error getting credentials: {e}")
        return None

    def format_reset_time(self, iso_timestamp, user_timezone="Europe/Bucharest"):
        """Format ISO timestamp to user-friendly reset time."""
        if not iso_timestamp:
            return "Unknown"
        try:
            # Parse ISO timestamp
            dt = datetime.fromisoformat(iso_timestamp.replace('Z', '+00:00'))

            # Convert to local time
            import zoneinfo
            try:
                local_tz = zoneinfo.ZoneInfo(user_timezone)
            except:
                local_tz = datetime.now().astimezone().tzinfo

            local_dt = dt.astimezone(local_tz)

            # Format nicely
            now = datetime.now(local_tz)

            # Check if it's today, tomorrow, or a specific date
            if local_dt.date() == now.date():
                time_str = local_dt.strftime("%I%p").lstrip('0').lower()
                return f"Resets today {time_str}"
            elif local_dt.date() == (now + timedelta(days=1)).date():
                time_str = local_dt.strftime("%I%p").lstrip('0').lower()
                return f"Resets tomorrow {time_str}"
            else:
                time_str = local_dt.strftime("%b %d, %I%p").replace(" 0", " ").lstrip('0')
                return f"Resets {time_str}".lower().replace("resets", "Resets")
        except Exception as e:
            print(f"Error formatting time: {e}")
            return f"Resets soon"

    def fetch_usage_data(self):
        """Fetch usage data from Claude API using OAuth token."""
        try:
            creds = self.get_credentials()
            if not creds or 'claudeAiOauth' not in creds:
                self.usage_data['status'] = 'no_auth'
                print("No Claude credentials found")
                return

            oauth = creds['claudeAiOauth']
            access_token = oauth.get('accessToken')

            if not access_token:
                self.usage_data['status'] = 'no_token'
                return

            # Check if token is expired
            expires_at = oauth.get('expiresAt', 0) / 1000  # Convert from ms
            if time.time() > expires_at:
                self.usage_data['status'] = 'token_expired'
                # Clear cache to force re-fetch on next try
                self._credentials_cache = None
                return

            # Call the OAuth usage endpoint
            headers = {
                'Authorization': f'Bearer {access_token}',
                'anthropic-beta': 'oauth-2025-04-20',
                'Content-Type': 'application/json'
            }

            response = requests.get(
                'https://api.anthropic.com/api/oauth/usage',
                headers=headers,
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                self.parse_api_response(data)
                self.usage_data['status'] = 'connected'
            elif response.status_code == 401:
                self.usage_data['status'] = 'auth_error'
                self._credentials_cache = None  # Clear cache
            else:
                self.usage_data['status'] = 'api_error'
                print(f"API error: {response.status_code} - {response.text}")

        except requests.exceptions.Timeout:
            self.usage_data['status'] = 'timeout'
        except requests.exceptions.ConnectionError:
            self.usage_data['status'] = 'no_connection'
        except Exception as e:
            self.usage_data['status'] = 'error'
            print(f"Error fetching usage: {e}")

        self.usage_data['last_updated'] = datetime.now().strftime("%H:%M:%S")

    def parse_api_response(self, data):
        """Parse the OAuth usage API response."""
        try:
            # Parse five_hour (session) data
            if 'five_hour' in data and data['five_hour']:
                five_hour = data['five_hour']
                self.usage_data['session']['used'] = int(five_hour.get('utilization', 0))
                self.usage_data['session']['reset_time'] = self.format_reset_time(
                    five_hour.get('resets_at')
                )

            # Parse seven_day (week all models) data
            if 'seven_day' in data and data['seven_day']:
                seven_day = data['seven_day']
                self.usage_data['week_all']['used'] = int(seven_day.get('utilization', 0))
                self.usage_data['week_all']['reset_time'] = self.format_reset_time(
                    seven_day.get('resets_at')
                )

            # Parse seven_day_sonnet data
            if 'seven_day_sonnet' in data and data['seven_day_sonnet']:
                sonnet = data['seven_day_sonnet']
                self.usage_data['week_sonnet']['used'] = int(sonnet.get('utilization', 0))
                self.usage_data['week_sonnet']['reset_time'] = self.format_reset_time(
                    sonnet.get('resets_at')
                )
            else:
                # If no sonnet-specific data, show as N/A
                self.usage_data['week_sonnet']['used'] = 0
                self.usage_data['week_sonnet']['reset_time'] = "No separate limit"

            # Parse extra usage
            if 'extra_usage' in data and data['extra_usage']:
                self.usage_data['extra_usage'] = data['extra_usage'].get('is_enabled', False)
            else:
                self.usage_data['extra_usage'] = False

        except Exception as e:
            print(f"Error parsing API response: {e}")

    def update_status(self, _):
        """Timer callback - updates every second."""
        # Fetch new data every 30 seconds, but update display every second
        current_second = datetime.now().second
        if current_second == 0 or current_second == 30:
            threading.Thread(target=self.fetch_usage_data, daemon=True).start()

        self.update_menu_display()

    def manual_refresh(self, _):
        """Manual refresh callback."""
        self.title = "◌ ..."
        self._credentials_cache = None  # Clear cache to force fresh fetch
        threading.Thread(target=self.fetch_usage_data, daemon=True).start()
        rumps.notification(
            title="Claude Status",
            subtitle="Refreshing",
            message="Fetching latest usage data..."
        )

    def quit_app(self, _):
        """Quit the application."""
        rumps.quit_application()


def main():
    """Main entry point."""
    print("Starting Claude Status Menu Bar App...")
    print("Look for the status icon in your menu bar!")

    app = ClaudeStatusApp()
    app.run()


if __name__ == "__main__":
    main()
