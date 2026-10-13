# Change things any time (no new APK)

Edit `assets/data/app_config.json` on GitHub: open the file, pencil icon,
change, **Commit changes**. Phones pick it up the next time the app opens or
comes back to the screen (GitHub can take a few minutes to refresh). Offline
phones use the last copy they saved. A key you delete uses the app's built-in
default, so you can never break the app by leaving something out.

```json
{
  "ads":    { "enabled": true, "supportUrl": "https://...", "intervalMinutes": 10, "skipAfterSeconds": 6 },
  "movies": { "embedBase": "https://vsembed.su/embed",
              "altEmbedBase": "https://web.nxsha.app/embed",
              "downloadBase": "https://web.nxsha.app/dl",
              "replaceHosts": ["vsembed.ru", "vsembed.su"] },
  "update": { "apkUrl": "", "version": "", "notes": "" },
  "chat":   { "enabled": true },
  "scores": { "enabled": true, "pollSeconds": 45,
              "url": "https://site.api.espn.com/apis/site/v2/sports/soccer/all/scoreboard" },
  "share":  { "message": "Get Deeprowss - live football, highlights, TV and movies",
              "link": "https://deeprowss.com" }
}
```

## Support ads
| Field | Meaning |
|---|---|
| `enabled` | `false` = no ads for anyone |
| `supportUrl` | The ad / smart link. Change it any time. Empty = no ads |
| `intervalMinutes` | Minutes of use between ads |
| `skipAfterSeconds` | Seconds after the ad loads before Skip Ad appears |

## Movies
Player links are built from the TMDB id: `<embedBase>/movie/<id>`,
`<embedBase>/tv/<id>`; backup player (Switch button) from `altEmbedBase`;
Download from `<downloadBase>/movie|tv/<id>`. Write the base **without** a
trailing slash and **without** the id. Rows in `movies.json` that still have a
full link on a host listed in `replaceHosts` are moved to `embedBase`
automatically; rows on other hosts are left alone.

## Update app
Put the **direct** link to the new `.apk` in `update.apkUrl` (it must end up
downloading the file, not show a web page). When someone taps **Update App**
in the menu the download starts right away with a progress bar, then Android's
installer opens. `version` and `notes` are optional labels for you. Empty
`apkUrl` = the button says "No update available right now". The new APK must be
signed with the same key as the installed one or Android refuses to install it.

## Live scores
Every match in `fixtures.json` is looked up by team names and kick-off time in
a free public football scoreboard (ESPN, no key). While the Live screen is open
the app checks every `pollSeconds` seconds; a found match shows the real score
and clock (`72'`, Half-time, Full-time) on its card. Matches not found keep the
normal countdown / timer. `"enabled": false` switches it off. `url` can point
to your own proxy as long as it returns ESPN-style JSON (`{"events": [...]}`).
Tips: write team names normally ("Manchester City" or "Man City" both work).
If a match never gets a score, add `"scoreLeague": "eng.1"` (ESPN's league
code) to that fixture so the app also asks that league's scoreboard. Make
`duration` long enough for the whole match, because the Live list sections are
still sorted by it.

## Share App
The menu's **Share App** sends the app's own APK file through the phone's share
sheet (Xender, SHAREit, WhatsApp...). `message` and `link` make the text that
goes with it: `message: link`. Put your download page in `link`. Empty `link`
= message only. Some apps (e.g. Xender) send only the file and ignore the text.

## Live chat
`"chat": { "enabled": false }` hides the match chat on football pages. Set
`true` to bring it back.
