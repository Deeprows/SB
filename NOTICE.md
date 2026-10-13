# Notice (change it any time, no new APK)

Edit `assets/data/notice.json` on GitHub (open the file, pencil icon, change,
**Commit**). Phones get the new text the next time they open the app or the
menu's **Notice** item (GitHub can take a few minutes to refresh).

```json
{
  "enabled": true,
  "id": "update-1",
  "title": "New version",
  "message": "Version 1.1 is out with faster downloads.",
  "popup": true,
  "button_text": "Update now",
  "button_url": "https://github.com/Deeprows/myflutter-app/releases/latest",
  "ok_text": "OK",
  "expires": "2026-12-31"
}
```

| Field         | Meaning                                                              |
|---------------|----------------------------------------------------------------------|
| `enabled`     | `false` = no notice (menu says "No new notices right now.")          |
| `id`          | **Change it for every new notice.** A pop-up shows once per id.      |
| `title`       | Heading                                                              |
| `message`     | The text                                                             |
| `popup`       | `true` = pops up when the app opens (once per id). `false` = only in the menu's Notice item |
| `button_text` + `button_url` | Optional button that opens a link (e.g. the new APK)  |
| `ok_text`     | Label of the close button                                            |
| `expires`     | Optional date `YYYY-MM-DD`; hidden after it                          |

To send a new pop-up to everyone, change `id` (and the text). To turn it off,
set `"enabled": false`. If the phone is offline it shows the last notice it
saved. A plain text file (no JSON) also works: the text becomes the message.
