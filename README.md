# ns8-dolibarr

[Dolibarr](https://www.dolibarr.org/) ERP and CRM for [NethServer 8](https://github.com/NethServer/ns8-core).

The module runs the official `dolibarr/dolibarr` image (Apache, PHP) with a MariaDB LTS database in the same rootless pod.
Traefik publishes it on a dedicated host name and always redirects HTTP to HTTPS.

Features:

- the password of the local `admin` account is set from NS8, it replaces the random password set at installation
- login with Dolibarr local accounts and with the users of one NS8 user domain (OpenLDAP or Active Directory)
- domain users are synchronized into Dolibarr at each configuration, and every hour with the hourly synchronization
- members of an optional domain group get the Dolibarr administrator flag
- emails through the cluster smarthost, when it is configured
- Dolibarr scheduled jobs run every 5 minutes
- default Dolibarr language chosen at configuration time
- database upgrade run by the module after an image update
- backup, restore and clone

## Install

Instantiate the module with:

    add-module ghcr.io/stephdl/dolibarr:latest 1

The output of the command will return the instance name.
Output example:

    {"module_id": "dolibarr1", "image_name": "dolibarr", "image_url": "ghcr.io/stephdl/dolibarr:latest"}

## Configure

Let's assume that the instance is named `dolibarr1`.

Launch `configure-module` with the following parameters:

- `host`: fully qualified domain name of the application
- `lets_encrypt`: request a Let's Encrypt certificate (true/false)
- `language`: default Dolibarr language, one of `auto` (browser language), `en_US`, `en_GB`, `fr_FR`, `it_IT`, `de_DE`, `es_ES`, `pt_PT`, `pt_BR`, `eu_ES`, `nl_NL`
- `user_domain`: NS8 user domain for LDAP login, empty for local accounts only
- `admin_group`: group of the user domain whose members get the Dolibarr administrator flag, empty for none
- `ldap_sync`: synchronize domain users every hour (true/false)
- `mail_from`: sender of Dolibarr emails, empty for `noreply@<host>`
- `admin_password`: password of the Dolibarr local `admin` account, at least 8 characters with lowercase and uppercase letters, a number and a symbol. Required at the first configuration, optional later

Example:

```bash
api-cli run configure-module --agent module/dolibarr1 --data - <<EOF
{
  "host": "dolibarr.domain.com",
  "lets_encrypt": false,
  "language": "fr_FR",
  "user_domain": "ad.domain.com",
  "admin_group": "Domain Admins",
  "ldap_sync": true,
  "mail_from": "",
  "admin_password": "Choose,a-strong1"
}
EOF
```

The first start installs the Dolibarr database, it takes about two minutes.
The company name and country are asked by Dolibarr at the first login of `admin`.
The web install wizard is denied: the module installs and upgrades the database from the command line.

The module writes its settings into Dolibarr at every configuration, app start, module update, smarthost change and user domain change.
Settings written by the module (language, sender, SMTP, LDAP) are overwritten if they are changed from the Dolibarr interface.

Get the current configuration with:

    api-cli run get-configuration --agent module/dolibarr1

## Users and groups

Dolibarr does not create users at their first LDAP login: a domain user must exist in Dolibarr first.
The module runs the Dolibarr script `sync_users_ldap2dolibarr.php` at each configuration, and once a day with `ldap_sync` through the `dolibarr-ldap-sync.timer` user unit.
It creates the missing users and updates their name, taken from `displayName`, and email. Passwords are never copied: the domain checks them at each login.
Users removed from the domain stay in Dolibarr with their history, and can no longer log in.

The "Synchronize users now" button of the Settings page runs the sync at once. From the command line:

    api-cli run sync-users --agent module/dolibarr1

Members of `admin_group` get the Dolibarr administrator flag, the other domain users lose it.
If the domain cannot be read, the flags are kept as they are.

Authentication is `ldap,dolibarr`: the local `admin` account always works, even when the user domain is down.
A domain user named `admin` is never synchronized and cannot log in, so it can never open the session of the local account.

## Email

Dolibarr uses the cluster smarthost settings in SMTP mode. When the smarthost is disabled, the module removes the SMTP settings it wrote, and an SMTP server set by hand in Dolibarr is kept.
The SMTP EHLO uses the Dolibarr host name.

## Scheduled jobs

The `dolibarr-cron.timer` user unit runs `scripts/cron/cron_run_jobs.php` every 5 minutes with the instance cron key.
Enable the jobs to run from the Dolibarr Scheduled jobs page.

## Backup, restore, clone

The backup contains a dump of the database, the secrets and the `dolibarr-documents` and `dolibarr-custom` volumes.
The secrets include `instance_unique_id`, which encrypts the LDAP, SMTP and cron passwords stored in the database: restore and clone keep it.
The `dolibarr-documents` volume can be placed on an additional disk at install time.

A cloned instance keeps the host name of its source and gets no Traefik route.
Set a new host name from the Settings page to make it reachable.

## Upgrade

The image entrypoint does not upgrade a database that is already installed.
After an image update, the module dumps the database to `state/dolibarr-before-update.sql`, restarts the services, then runs the Dolibarr upgrade scripts once if the files are newer than the database.
The result is logged in the module journal and in `documents/ns8-upgrade.log`.
An app stopped during the update runs the upgrade at its next start.

Renovate opens the image update PRs. MariaDB stays on the 12.3 LTS branch. Only plain `x.y.z` Dolibarr tags are proposed, and major upgrades are not merged automatically.
The About page shows the Dolibarr version next to the module version.

## Debug

Show the module environment:

    runagent -m dolibarr1 env

Open a shell in the Dolibarr container:

    runagent -m dolibarr1 podman exec -ti dolibarr-app bash

Apply the module settings to Dolibarr again:

    runagent -m dolibarr1 systemctl --user start dolibarr-apply-config.service

Run the domain users synchronization now:

    runagent -m dolibarr1 systemctl --user start dolibarr-ldap-sync.service

## Uninstall

To uninstall the instance:

    remove-module --no-preserve dolibarr1

## Testing

Test the module using the `test-module.sh` script:

    ./test-module.sh <NODE_ADDR> ghcr.io/stephdl/dolibarr:latest

The tests are made using [Robot Framework](https://robotframework.org/).

## UI translation

The UI is translated in English, French, Italian, German, Spanish, Portuguese, Brazilian Portuguese and Basque, in `ui/public/i18n/<lang>/translation.json`.
