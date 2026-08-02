# Flea Market by Kafeena — Discord Bridge

Optional Discord notification helper for the **Flea Market by Kafeena** Project Zomboid mod.

The Project Zomboid Workshop mod works without this download. This bridge is only needed when a server owner wants flea-market events posted to a Discord channel.

## What it posts

Depending on the Flea Market sandbox settings, the bridge can post:

- New listings
- Completed sales
- What's Hot promotions
- Player cancellations
- Expired listings
- Admin removals
- Admin test messages

## Windows quick setup

1. Download the latest release ZIP from this repository's **Releases** page.
2. Extract the ZIP somewhere permanent, such as:

   ```text
   C:\PZ Tools\Flea Market Discord Bridge
   ```

3. In Discord, open your server and go to:

   ```text
   Server Settings > Integrations > Webhooks > New Webhook
   ```

4. Choose the channel, name the webhook, and copy its URL.
5. Run `START_DISCORD_BRIDGE.bat`.
6. Paste the webhook URL and press Enter.
7. Enter the server name you want shown in Discord.
8. Leave the role ID blank unless you want a role mentioned for new/promoted listings.
9. Press Enter to accept the default audit-log path:

   ```text
   %USERPROFILE%\Zomboid\Lua\KafeenaFleaMarket_Audit.log
   ```

10. Leave the bridge window open while the Project Zomboid server is running.

The private webhook and bridge progress are stored outside this download under:

```text
%USERPROFILE%\Zomboid\Lua\KafeenaFleaMarketBridge
```

Do not upload or share the private files in that folder.

## Enable Discord events in Project Zomboid

In the world's or server's sandbox settings, open **Flea Market** and enable:

- Enable Discord Notifications
- Post New Listings
- Any other event types you want posted

Save the settings and fully restart the world/server.

Existing listings are not posted retroactively. Create a new listing after Discord is enabled.

## Test it

1. Start the bridge.
2. Open a registered Flea Market broker as an authorized admin.
3. Open the **Admin** tab.
4. Press **Test Discord Queue**.

The bridge should detect the test line in:

```text
%USERPROFILE%\Zomboid\Lua\KafeenaFleaMarket_Audit.log
```

and send a test message to Discord.

## Changing or replacing the webhook

Run:

```text
RESET_DISCORD_SETUP.bat
```

Then run `START_DISCORD_BRIDGE.bat` again.

If a webhook URL is ever posted publicly, delete that webhook in Discord and create a new one.

## Local and dedicated servers

The bridge must be able to read the same audit log that the Project Zomboid server writes.

- **Hosted on your Windows PC:** run the bridge on that same PC and Windows account.
- **Dedicated server on another PC:** run the bridge on that server PC, or point it to a shared/synchronized audit log.
- **Rented game host:** the host must allow an external PowerShell/Python process or give you another way to access the live audit log. The mod itself still works if the bridge cannot be used.

## Advanced/Linux setup

Advanced Python files are included under `Advanced/`. Copy `config.example.json` to `config.json`, add the private webhook, set the audit-log path, and run `discord_bridge.py` with Python 3.

## Security

Never commit or upload:

- `discord_private.json`
- `discord_bridge_state.json`
- `config.json` containing a real webhook
- Screenshots showing the complete webhook URL

Only the example configuration belongs in this repository.
