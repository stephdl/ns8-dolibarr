<?php

/*
 * Copyright (C) 2026 Nethesis S.r.l.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Apply the NS8 module settings to the Dolibarr database.
 * Run inside the dolibarr-app container, settings come from NS8_* environment variables:
 * the user domain ones from the container environment (ldap.env), the others from podman exec.
 * NS8_STEP=admins only sets the admin flag of the LDAP users, after a synchronization.
 * Idempotent: every run converges to the same state.
 */

// STDERR is not defined when PHP reads the script from stdin
if (!defined('STDERR')) {
    define('STDERR', fopen('php://stderr', 'w'));
}

define('NOSESSION', 1);
define('NOREQUIREHTML', 1);
define('NOREQUIREAJAX', 1);

require '/var/www/html/master.inc.php';
require_once DOL_DOCUMENT_ROOT . '/core/lib/admin.lib.php';
require_once DOL_DOCUMENT_ROOT . '/user/class/user.class.php';

const NS8_LOCAL_ADMIN = 'admin';

function env(string $name, string $default = ''): string
{
    $value = getenv($name);
    return $value === false ? $default : $value;
}

function logmsg(string $message): void
{
    fwrite(STDERR, $message . PHP_EOL);
}

function fail(string $message): never
{
    logmsg('ERROR: ' . $message);
    exit(1);
}

function set_const(string $name, string $value): void
{
    global $db, $conf;

    // An empty value deletes the constant
    if (dolibarr_set_const($db, $name, $value, 'chaine', 0, 'Managed by NethServer 8', $conf->entity) < 0) {
        fail("cannot set $name");
    }
}

// The admin flag can be changed only by an admin user, and the CLI has none
function system_actor(): User
{
    global $db;

    $actor = new User($db);
    $actor->id = 0;
    $actor->admin = 1;
    return $actor;
}

function apply_general_config(): void
{
    $host = env('NS8_HOST');

    set_const('MAIN_LANG_DEFAULT', env('NS8_LANGUAGE', 'auto'));
    set_const('MAIN_MAIL_EMAIL_FROM', env('NS8_MAIL_FROM') ?: 'noreply@' . $host);
    set_const('MAIN_SECURITY_HASH_ALGO', 'password_hash');
    // Without it Dolibarr also stores the clear password in llx_user.pass
    set_const('DATABASE_PWD_ENCRYPTED', '1');

    foreach (['modCron'] as $module) {
        $result = activateModule($module);
        if (!empty($result['errors'])) {
            fail("cannot enable $module: " . implode(', ', $result['errors']));
        }
    }
    // From the container environment, like the cron timer. dolibarr_set_const encrypts it.
    if (env('DOLI_CRON_KEY') === '') {
        fail('DOLI_CRON_KEY is missing from the container environment');
    }
    set_const('CRON_KEY', env('DOLI_CRON_KEY'));

    if (env('NS8_SMTP_ENABLED') === '1') {
        $encryption = env('NS8_SMTP_ENCRYPTION');
        set_const('MAIN_MAIL_SENDMODE', 'smtps');
        set_const('MAIN_MAIL_SMTP_SERVER', env('NS8_SMTP_HOST'));
        set_const('MAIN_MAIL_SMTP_PORT', env('NS8_SMTP_PORT', '25'));
        set_const('MAIN_MAIL_SMTPS_ID', env('NS8_SMTP_USERNAME'));
        set_const('MAIN_MAIL_SMTPS_PW', env('NS8_SMTP_PASSWORD'));
        set_const('MAIN_MAIL_EMAIL_TLS', $encryption === 'tls' ? '1' : '');
        set_const('MAIN_MAIL_EMAIL_STARTTLS', $encryption === 'starttls' ? '1' : '');
        set_const('MAIN_MAIL_EMAIL_SMTP_ALLOW_SELF_SIGNED', env('NS8_SMTP_TLSVERIFY') === '1' ? '' : '1');
        set_const('NS8_SMTP_MANAGED', '1');
    } elseif (getDolGlobalString('NS8_SMTP_MANAGED')) {
        // Only undo what NS8 wrote: an SMTP server set by hand in Dolibarr stays
        foreach (['MAIN_MAIL_SMTP_SERVER', 'MAIN_MAIL_SMTP_PORT', 'MAIN_MAIL_SMTPS_ID', 'MAIN_MAIL_SMTPS_PW',
                  'MAIN_MAIL_EMAIL_TLS', 'MAIN_MAIL_EMAIL_STARTTLS', 'MAIN_MAIL_EMAIL_SMTP_ALLOW_SELF_SIGNED',
                  'NS8_SMTP_MANAGED'] as $name) {
            set_const($name, '');
        }
        set_const('MAIN_MAIL_SENDMODE', 'mail');
    }
    logmsg('General and mail settings applied (smtp ' . (env('NS8_SMTP_ENABLED') === '1' ? 'enabled' : 'disabled') . ')');
}

function apply_local_admin(): void
{
    global $db;

    $password = env('NS8_ADMIN_PASSWORD');
    if ($password === '') {
        return;
    }
    $admin = new User($db);
    if ($admin->fetch(0, NS8_LOCAL_ADMIN) <= 0) {
        fail('local admin user not found');
    }
    if (dol_verifyHash($password, $admin->pass_indatabase_crypted)) {
        logmsg('Password of the admin user unchanged');
    } elseif ($admin->setPassword(system_actor(), $password) !== $password) {
        fail('cannot set the admin user password');
    } else {
        logmsg('Password of the admin user changed');
    }
    // Read by dolibarr-apply-config, even when a later LDAP step fails
    echo "NS8_ADMIN_PASSWORD_APPLIED\n";
}

function apply_ldap(): void
{
    if (env('NS8_LDAP_DOMAIN') === '') {
        // Keep the synchronized users: they log in again if a domain comes back
        foreach (['LDAP_SERVER_HOST', 'LDAP_ADMIN_DN', 'LDAP_ADMIN_PASS', 'LDAP_USER_DN', 'LDAP_FILTER_CONNECTION'] as $name) {
            set_const($name, '');
        }
        logmsg('LDAP settings removed');
        return;
    }

    $is_ad = env('NS8_LDAP_SCHEMA') === 'ad';
    $login_field = env('NS8_LDAP_LOGIN_ATTRIBUTE');
    $values = [
        'LDAP_SERVER_HOST'            => env('NS8_LDAP_HOST'),
        'LDAP_SERVER_PORT'            => env('NS8_LDAP_PORT'),
        'LDAP_SERVER_PROTOCOLVERSION' => '3',
        'LDAP_SERVER_TYPE'            => $is_ad ? 'activedirectory' : 'openldap',
        'LDAP_SERVER_USE_TLS'         => '',
        'LDAP_ADMIN_DN'               => env('NS8_LDAP_BIND_DN'),
        'LDAP_ADMIN_PASS'             => env('NS8_LDAP_BIND_PASSWORD'),
        'LDAP_USER_DN'                => env('NS8_LDAP_BASE_DN'),
        // getRecords() adds the outer parentheses
        'LDAP_FILTER_CONNECTION'      => substr(env('NS8_LDAP_USERS_FILTER'), 1, -1),
        'LDAP_KEY_USERS'              => $login_field,
        'LDAP_FIELD_LOGIN'            => $login_field,
        'LDAP_FIELD_MAIL'             => 'mail',
        'LDAP_FIELD_PHONE'            => 'telephonenumber',
        'LDAP_FIELD_MOBILE'           => 'mobile',
        // NS8 OpenLDAP splits the display name badly into cn and sn, and NS8 Samba
        // leaves sn and givenName empty: displayName is the only reliable name
        'LDAP_FIELD_NAME'             => 'displayname',
        'LDAP_FIELD_FIRSTNAME'        => '',
        // Never copy a password from the directory
        'LDAP_FIELD_PASSWORD'         => '',
        'LDAP_FIELD_PASSWORD_CRYPTED' => '',
    ];
    foreach ($values as $name => $value) {
        set_const($name, $value);
    }
    logmsg('LDAP settings applied for ' . env('NS8_LDAP_DOMAIN'));
}

function ldap_bind_ns8()
{
    $connection = ldap_connect('ldap://' . env('NS8_LDAP_HOST') . ':' . env('NS8_LDAP_PORT'));
    ldap_set_option($connection, LDAP_OPT_PROTOCOL_VERSION, 3);
    ldap_set_option($connection, LDAP_OPT_REFERRALS, 0);
    ldap_set_option($connection, LDAP_OPT_NETWORK_TIMEOUT, 10);
    if (!@ldap_bind($connection, env('NS8_LDAP_BIND_DN'), env('NS8_LDAP_BIND_PASSWORD'))) {
        fail('LDAP bind failed: ' . ldap_error($connection));
    }
    return $connection;
}

/** Return the logins of the entries matching $filter, lower case. */
function ldap_logins($connection, string $filter): array
{
    $field = env('NS8_LDAP_LOGIN_ATTRIBUTE');
    $result = @ldap_search($connection, env('NS8_LDAP_BASE_DN'), $filter, [$field]);
    if ($result === false) {
        fail('LDAP search failed: ' . ldap_error($connection));
    }
    $logins = [];
    foreach (ldap_get_entries($connection, $result) as $key => $entry) {
        if (is_int($key) && isset($entry[$field][0])) {
            $logins[] = strtolower($entry[$field][0]);
        }
    }
    return $logins;
}

/** Return the logins of the admin group members, or null when the group does not exist. */
function admin_group_logins($connection, string $group): ?array
{
    $name = ldap_escape($group, '', LDAP_ESCAPE_FILTER);
    if (env('NS8_LDAP_SCHEMA') === 'ad') {
        $result = @ldap_search($connection, env('NS8_LDAP_BASE_DN'), "(&(objectClass=group)(|(cn=$name)(sAMAccountName=$name)))", ['dn']);
        $entries = $result ? ldap_get_entries($connection, $result) : ['count' => 0];
        if ($entries['count'] === 0) {
            return null;
        }
        $dn = ldap_escape($entries[0]['dn'], '', LDAP_ESCAPE_FILTER);
        return ldap_logins($connection, "(&(objectClass=user)(memberOf=$dn))");
    }
    $result = @ldap_search($connection, env('NS8_LDAP_BASE_DN'), "(&(objectClass=posixGroup)(cn=$name))", ['memberuid']);
    $entries = $result ? ldap_get_entries($connection, $result) : ['count' => 0];
    if ($entries['count'] === 0) {
        return null;
    }
    $members = $entries[0]['memberuid'] ?? ['count' => 0];
    unset($members['count']);
    return array_map('strtolower', $members);
}

function apply_admin_flags(): void
{
    global $db;

    if (env('NS8_LDAP_DOMAIN') === '') {
        return;
    }
    // Resolve the directory first: a bind failure exits and keeps the current flags
    $connection = ldap_bind_ns8();
    $ldap_users = ldap_logins($connection, env('NS8_LDAP_USERS_FILTER'));
    $group = env('NS8_ADMIN_GROUP');
    $admins = $group === '' ? [] : admin_group_logins($connection, $group);
    ldap_unbind($connection);
    if ($admins === null) {
        logmsg("WARNING: LDAP group $group not found, LDAP users lose the admin rights");
        $admins = [];
    }

    $sql = 'SELECT rowid, login, admin FROM ' . MAIN_DB_PREFIX . "user WHERE login <> '" . $db->escape(NS8_LOCAL_ADMIN) . "'";
    $resql = $db->query($sql);
    if (!$resql) {
        fail('cannot list users: ' . $db->lasterror());
    }
    while ($row = $db->fetch_object($resql)) {
        $login = strtolower($row->login);
        if (!in_array($login, $ldap_users, true)) {
            continue;
        }
        $wanted = in_array($login, $admins, true) ? 1 : 0;
        if ((int) $row->admin === $wanted) {
            continue;
        }
        $target = new User($db);
        $target->fetch($row->rowid);
        $target->admin = $wanted;
        if ($target->update(system_actor()) < 0) {
            fail("cannot update the admin flag of {$row->login}");
        }
        logmsg(($wanted ? 'Admin rights given to ' : 'Admin rights removed from ') . $row->login);
    }
}

if (env('NS8_STEP') === 'admins') {
    apply_admin_flags();
} else {
    apply_general_config();
    // Before LDAP: an LDAP failure must not leave the bootstrap admin password in place
    apply_local_admin();
    apply_ldap();
}
