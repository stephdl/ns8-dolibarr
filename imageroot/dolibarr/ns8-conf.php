<?php

/*
 * Copyright (C) 2026 Nethesis S.r.l.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Run as root by the image entrypoint (before-starting.d) after it writes conf.php.
 * Append the settings the entrypoint does not write. A later assignment wins in PHP,
 * and var_export() escapes values the entrypoint would copy raw between quotes.
 */

$conf_file = '/var/www/html/conf/conf.php';

$settings = [
    'dolibarr_main_force_https'     => '1',
    'dolibarr_main_authentication'  => 'dolibarr',
];

if (getenv('NS8_LDAP_HOST')) {
    $is_ad = getenv('NS8_LDAP_SCHEMA') === 'ad';
    $login = $is_ad ? 'samaccountname' : 'uid';
    $settings = array_merge($settings, [
        // The local admin still logs in when the directory is down
        'dolibarr_main_authentication'           => 'ldap,dolibarr',
        'dolibarr_main_auth_ldap_host'           => getenv('NS8_LDAP_HOST'),
        'dolibarr_main_auth_ldap_port'           => getenv('NS8_LDAP_PORT'),
        'dolibarr_main_auth_ldap_version'        => '3',
        'dolibarr_main_auth_ldap_servertype'     => $is_ad ? 'activedirectory' : 'openldap',
        'dolibarr_main_auth_ldap_login_attribute' => $login,
        'dolibarr_main_auth_ldap_dn'             => getenv('NS8_LDAP_BASE_DN'),
        'dolibarr_main_auth_ldap_filter'         => getenv('NS8_LDAP_LOGIN_FILTER'),
        'dolibarr_main_auth_ldap_admin_login'    => getenv('NS8_LDAP_BIND_DN'),
        'dolibarr_main_auth_ldap_admin_pass'     => getenv('NS8_LDAP_BIND_PASSWORD'),
        'dolibarr_main_auth_ldap_debug'          => 'false',
    ]);
}

$lines = "\n// Managed by NethServer 8\n";
foreach ($settings as $name => $value) {
    $lines .= '$' . $name . '=' . var_export((string) $value, true) . ";\n";
}

chmod($conf_file, 0600);
if (file_put_contents($conf_file, $lines, FILE_APPEND) === false) {
    exit(1);
}
chmod($conf_file, 0400);
echo "NS8 settings appended to conf.php\n";
