# Abil.py workshop landing page

This repository publishes a lightweight static landing page for the **MASTS ASM 2026 Abil.py practical** on Thursday 12 November 2026, 10:50–15:15 GMT. Its intended address is `https://workshop.nanophyto.org`.

The page shows **29 workstations together**, identified by their `@nanophyto.org` account display names and full sign-in addresses, such as **Cheerful Crab** (`cheerfulcrab@nanophyto.org`). Names are taken from the Cloud Identity export supplied on 11 November. the administrative account is excluded. The page displays the pseudonymous workshop sign-in addresses but contains no passwords, login tokens, participant roles or organiser assignments. Cloud Workstations continues to enforce Google account authentication and IAM permissions after a user clicks a link.

The page opens directly on the workstation selector, showing each friendly name and full sign-in address. The extra three-step guide and support panel have been removed for a simpler layout.

## Publish at workshop.nanophyto.org

The `.github/workflows/documentation.yml` workflow builds and deploys **only `site/`** using GitHub Pages. It validates the account configuration and JavaScript, and does not run Documenter, Julia simulations or scientific documentation builds.

1. In the GitHub repository, select **Settings → Pages → Build and deployment → GitHub Actions**. Ensure Pages is enabled.
2. Push the patch to `main`. The **Workshop landing page** workflow runs automatically. You can also use **Actions → Workshop landing page → Run workflow**.
3. Under **Settings → Pages → Custom domain**, enter `workshop.nanophyto.org` and save.
4. In Cloudflare DNS for `nanophyto.org`, create a **CNAME** record with **Name** `workshop`, **Target** `nanophyto.github.io`, **DNS only**. It does not change root-domain forwarding.
5. Enable **Enforce HTTPS** when GitHub has provided its certificate. Confirm the page works in a private browser window.

## Add or change workstation links tomorrow

The **single editable URL file** is `site/workstations.json`:

```json
{
  "schemaVersion": 2,
  "accounts": [
    {"name": "Cheerful Crab", "username": "cheerfulcrab", "url": null}
  ]
}
```

The snippet illustrates a single account entry; the actual JSON contains **all 29 accounts**. Leave `url` as `null` until a workstation is ready. Once configured, the associated **Open workstation** link becomes active.

The names, including the precise spelling **Cheerful** (not *Cheerfull*), match the uploaded Google account roster. This avoids confusion between the visible label, the account username and the workstation assignment.

### Update one account

```bash
cd ~/masts-asm-2026-modelling
python3 scripts/update_landing_page.py --set cheerfulcrab 'https://ACTUAL-STATION.cloudworkstations.dev'
python3 scripts/update_landing_page.py --check
```

`--set 'Cheerful Crab'` and `--set cheerfulcrab@nanophyto.org` also identify the same account. The helper validates the Google Cloud Workstations hostname and adds a `folder` query parameter so that the editor opens `/home/user/masts-asm-2026-modelling/workshop/02_Abil`.

### Update many accounts from a CSV

Prepare a local file containing account usernames and URLs, for example:

```csv
account,launch_url
cheerfulcrab@nanophyto.org,https://YOUR-LONDON-STATION.cloudworkstations.dev
wisewalrus@nanophyto.org,https://YOUR-BELGIUM-STATION.cloudworkstations.dev
```

Then run:

```bash
cd ~/masts-asm-2026-modelling
python3 scripts/update_landing_page.py --csv /path/to/account-workstation-links.csv
python3 scripts/update_landing_page.py --check
```

The importer also accepts `username,url` and the `workstation,account,launch_url` CSV produced by `scripts/workstation_links.py`. **The account column determines the assignment**, even if an underlying VM is named `mast-01`, `mast-29`, or similar. An account can therefore be moved between London and Belgium without changing its name on the landing page. The CSV's email addresses are used for matching. Only the pseudonymous usernames are stored in the public JSON; the browser appends `@nanophyto.org` for display.

### Import directly from private cloud-workshops status output

If your deployment script emits four columns of the form `workstation STATE_* account URL`, use:

```bash
cd ~/masts-asm-2026-modelling
python3 scripts/update_landing_page.py --from-status --reset < /tmp/london.status
python3 scripts/update_landing_page.py --from-status < /tmp/belgium.status
python3 scripts/update_landing_page.py --check
```

`--reset` clears stale URLs at the start of a new deployment; the second invocation merges the Belgium links with London's. Both imports assign URLs by the Google **account**, not by workstation number. The tool reports unknown accounts, duplicate entries, unsupported URLs and duplicate workstation assignments before writing its output. If your deployment status format differs, use the CSV import format above.

### Publish changed links

```bash
cd ~/masts-asm-2026-modelling
python3 scripts/update_landing_page.py --check
git add site/workstations.json
git commit -m "Update Abil workstation launch links"
git push
```

GitHub Pages redeploys the static page on push. Visitors get fresh account URLs after refreshing the website. There is no need to rebuild the workstation container.

## Preview and test

```bash
cd ~/masts-asm-2026-modelling
python3 scripts/update_landing_page.py --check
python3 -m unittest discover -s tests -p 'test_landing_*.py' -v
node --check site/app.js
python3 -m http.server 8000 --directory site
```

Open `http://localhost:8000`. Try filtering for `Cheerful Crab`, `cheerfulcrab`, `cheerfulcrab@nanophyto.org`, `crab`, and another displayed account. The selected link opens in a separate browser tab.

## Security and access

- The landing page is **public**. Display names and full `@nanophyto.org` sign-in addresses are pseudonymous, but visible to site visitors.
- Password resets and invitation instructions should be sent to each person through the Google Cloud Identity or university email workflow; no passwords are stored here.
- Underlying workstation URLs, if published, remain protected by Google Cloud authentication and IAM permissions.
- Ask users to open the page in a private/incognito window if a different Google account is already signed in.
- The public roster excludes `admin@nanophyto.org`.
