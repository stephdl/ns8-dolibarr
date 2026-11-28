*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${ADMIN_USER}        admin
${ADMIN_PASSWORD}    Nethesis,1234
# Any resolvable-looking name: the schema demands a dot, nothing resolves it.
${TEST_HOST}         dolibarr.ns8-ci.test
${DOLI_PASSWORD}     Ns8,Doli-Test1
${BASE_CONFIG}       "host":"${TEST_HOST}","lets_encrypt":false,"user_domain":"","admin_group":"","ldap_sync":false,"mail_from":"","language":"auto"
${SCENARIO}          install
${SQL}               podman exec mariadb-app sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N dolibarr -e "$0"'
${CI_USER_PASSWORD}  Ci,User-Pass1
# The rows the tests read back, written as the admin through Dolibarr classes like the UI does.
# The encrypted constant fails to decrypt if the instance id changes. Single quotes stay out of the PHP code.
${FILL_DATA}         define("NOREQUIREUSER", 1); define("NOREQUIRETRAN", 1); define("NOCSRFCHECK", 1); chdir("/var/www/html"); require "/var/www/html/master.inc.php"; require_once DOL_DOCUMENT_ROOT."/user/class/user.class.php"; require_once DOL_DOCUMENT_ROOT."/core/lib/admin.lib.php"; require_once DOL_DOCUMENT_ROOT."/societe/class/societe.class.php"; require_once DOL_DOCUMENT_ROOT."/compta/facture/class/facture.class.php"; $user = new User($db); $user->fetch(0, "admin"); $user->loadRights(); $db->begin(); $s = new Societe($db); $s->name = "CI Update Test"; $s->client = 1; $s->code_client = "CI-UPDATE"; $sid = $s->create($user); $f = new Facture($db); $f->socid = $sid; $f->type = 0; $f->date = dol_now(); $fid = $f->create($user); $lid = $f->addline("CI update line", 100, 2, 20); $u = new User($db); $u->login = "ciuser"; $u->lastname = "CI User"; $u->entity = 1; $uid = $u->create($user); $pw = $u->setPassword($user, "${CI_USER_PASSWORD}"); $c = dolibarr_set_const($db, "CI_UPDATE_CRYPTED", dolEncrypt("ci-secret-42"), "chaine", 0, "", 1); if ($sid <= 0 || $fid <= 0 || $lid <= 0 || $uid <= 0 || $pw < 0 || $c <= 0) { fwrite(STDERR, "add failed: ".$db->lasterror()); exit(1); } $db->commit(); echo "ok";
${READ_DATA}         define("NOREQUIREUSER", 1); define("NOREQUIRETRAN", 1); chdir("/var/www/html"); require "/var/www/html/master.inc.php"; require_once DOL_DOCUMENT_ROOT."/compta/facture/class/facture.class.php"; $row = $db->fetch_object($db->query("SELECT s.nom, f.rowid FROM ".MAIN_DB_PREFIX."societe AS s JOIN ".MAIN_DB_PREFIX."facture AS f ON f.fk_soc = s.rowid WHERE s.code_client = \\"CI-UPDATE\\"")); $f = new Facture($db); $f->fetch($row->rowid); $raw = $db->fetch_object($db->query("SELECT value FROM ".MAIN_DB_PREFIX."const WHERE name = \\"CI_UPDATE_CRYPTED\\""))->value; echo json_encode([$row->nom, count($f->lines), (float) $f->total_ht, $f->lines[0]->desc, substr($raw, 0, 9), dolDecrypt($raw)]);

*** Keywords ***
Login to cluster-admin
    New Page    https://${NODE_ADDR}/cluster-admin/
    Fill Text    text="Username"    ${ADMIN_USER}
    Click    button >> text="Continue"
    Fill Text    text="Password"    ${ADMIN_PASSWORD}
    Click    button >> text="Log in"
    Wait For Elements State    css=#main-content    visible    timeout=10s

HTTP code
    [Arguments]    ${url}    ${options}=${EMPTY}
    ${code} =    Execute Command    curl -sk ${options} -o /dev/null -w "\%{http_code}" -H "Host: ${TEST_HOST}" ${url}
    RETURN    ${code}

Dolibarr answers
    ${code} =    HTTP code    https://127.0.0.1/
    Should Be Equal    ${code}    200

Enable the stephdl forge
    # The module is published there, not in the default NS8 repositories
    ${rc} =    Execute Command
    ...    api-cli run add-repository --data '{"name":"stephdl","url":"https://forge.de-labrusse.fr/ns8/updates/","status":true}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Dolibarr php
    [Arguments]    ${code}
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} podman exec -u www-data dolibarr-app php -r '${code}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    RETURN    ${output}

Run SQL
    [Arguments]    ${query}
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} ${SQL} '${query}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    RETURN    ${output}

Saved data
    ${rows} =    Dolibarr php    ${READ_DATA}
    ${file} =    Execute Command    runagent -m ${module_id} podman exec dolibarr-app cat /var/www/documents/ci-update.txt
    RETURN    ${rows}|${file}

Log in to Dolibarr
    [Arguments]    ${user}    ${password}
    # The login form needs the session cookie and the CSRF token of the first GET
    ${page} =    Execute Command
    ...    jar=$(mktemp); url=https://${TEST_HOST}; opt="-sk -c $jar -b $jar --resolve ${TEST_HOST}:443:127.0.0.1"; token=$(curl $opt $url/ | sed -n 's/.*name="token" value="\\([^"]*\\)".*/\\1/p' | head -1); curl $opt -L --data-urlencode "token=$token" --data-urlencode 'actionlogin=login' --data-urlencode 'loginfunction=loginfunction' --data-urlencode 'username=${user}' --data-urlencode 'password=${password}' $url/index.php; rm -f $jar
    RETURN    ${page}

*** Test Cases ***
Check if dolibarr is installed correctly
    # The update scenario starts from the release published in the stephdl forge,
    # and moves it to the image under test after the first checks
    IF    '${SCENARIO}' == 'update'
        Enable the stephdl forge
        ${image} =    Set Variable    dolibarr
    ELSE
        ${image} =    Set Variable    ${IMAGE_URL}
    END
    ${output}  ${rc} =    Execute Command    add-module ${image} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Suite Variable    ${module_id}    ${output.module_id}

Check the fresh configuration
    # A fresh instance only: the install scenario covers it
    Skip If    '${SCENARIO}' == 'update'    the update scenario starts from a configured release
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Not Be True    ${config['admin_password_set']}

Check a missing admin password is rejected
    # A fresh instance only: the install scenario covers it
    Skip If    '${SCENARIO}' == 'update'    the update scenario starts from a configured release
    ${output} =    Run task    module/${module_id}/configure-module    {${BASE_CONFIG}}
    ...    decode_json=${FALSE}    rc_expected=2
    Should Contain    ${output}    admin_password_required

Check a weak admin password is rejected
    ${output} =    Run task    module/${module_id}/configure-module    {${BASE_CONFIG},"admin_password":"abcdefgh"}
    ...    decode_json=${FALSE}    rc_expected=2
    Should Contain    ${output}    admin_password_too_weak

Check if dolibarr can be configured
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG},"admin_password":"${DOLI_PASSWORD}"}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${config['host']}    ${TEST_HOST}
    Should Be True    ${config['admin_password_set']}
    Should Be True    ${config['route_configured']}

Check services are running
    ${status} =    Run task    module/${module_id}/get-status    null
    FOR    ${service}    IN    @{status['services']}
        # Oneshot units started by their timer are inactive between runs
        IF    $service['name'] in ['dolibarr-ldap-sync', 'dolibarr-cron', 'dolibarr-apply-config']    CONTINUE
        Should Be True    ${service['active']}    ${service['name']} is not active
    END

Check if dolibarr works as expected
    # The first start installs the database, so give it more time than a warm start
    Wait Until Keyword Succeeds    30 times    10 seconds    Dolibarr answers
    # HTTP to HTTPS redirection is always on
    ${code} =    HTTP code    http://127.0.0.1/
    Should Match Regexp    ${code}    ^30[178]$

Fill dolibarr with data
    # Install checks the writes on the image under test, update checks they survive it
    ${output} =    Dolibarr php    ${FILL_DATA}
    Should Be Equal    ${output}    ok
    ${rc} =    Execute Command    runagent -m ${module_id} podman exec -u www-data dolibarr-app sh -c 'echo saved-by-the-ci > /var/www/documents/ci-update.txt'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${data} =    Saved data
    Set Suite Variable    ${data_before}    ${data}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Set Suite Variable    ${config_before}    ${config}
    ${image} =    Execute Command    runagent -m ${module_id} printenv DOLIBARR_IMAGE
    Set Suite Variable    ${dolibarr_image_before}    ${image}

Update dolibarr to the image under test
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${rc} =    Execute Command
    ...    api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${module_id}"]}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${image} =    Execute Command    runagent -m ${module_id} printenv IMAGE_URL
    Should Be Equal    ${image}    ${IMAGE_URL}
    # A newer release in the forge than the image under test would downgrade the database
    ${dolibarr_image} =    Execute Command    runagent -m ${module_id} printenv DOLIBARR_IMAGE
    ${newer} =    Evaluate    [int(x) for x in $dolibarr_image.rsplit(":", 1)[1].split(".")] >= [int(x) for x in $dolibarr_image_before.rsplit(":", 1)[1].split(".")]
    Should Be True    ${newer}    the stable release runs ${dolibarr_image_before}, newer than ${dolibarr_image}
    # The database upgrade runs once Apache answers, wait for it to end
    ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user start dolibarr-apply-config
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    Wait Until Keyword Succeeds    30 times    10 seconds    Dolibarr answers

Check the settings survive the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    # Only the keys the stable release had: a new release may add settings
    # Robot variables are not visible inside a comprehension body: map() reads them outside it
    ${changed} =    Evaluate    [k for k, old, new in zip($config_before.keys(), $config_before.values(), map($config.get, $config_before)) if old != new]
    Should Be Empty    ${changed}

Check the data is still there
    # Right after the writes in the install scenario, after the update in the other one
    ${data} =    Saved data
    Should Be Equal    ${data}    ${data_before}
    Should Be Equal    ${data}    ["CI Update Test",1,200,"CI update line","dolcrypt:","ci-secret-42"]|saved-by-the-ci
    ${page} =    Log in to Dolibarr    ciuser    ${CI_USER_PASSWORD}
    Should Contain    ${page}    logout.php

Check the database matches the new release
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update
    ${version} =    Run SQL    SELECT value FROM llx_const WHERE name = "MAIN_VERSION_LAST_UPGRADE"
    ${files} =    Execute Command    runagent -m ${module_id} podman exec dolibarr-app printenv DOLI_VERSION
    Should Be Equal    ${version}    ${files}
    ${rc} =    Execute Command    runagent -m ${module_id} test -s dolibarr-before-update.sql
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0    the dump taken before the update is missing

Check if the bootstrap admin password is replaced
    # The image entrypoint stores an md5 hash, Dolibarr password_hash starts with $2y$
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} podman exec mariadb-app sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N dolibarr -e "SELECT LEFT(pass_crypted, 4), pass IS NULL FROM llx_user WHERE login = \\"admin\\""'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Should Be Equal    ${output}    $2y$\t1

Check the admin can log in
    ${page} =    Log in to Dolibarr    admin    ${DOLI_PASSWORD}
    # The logout link is only in the menu of a logged in user
    Should Contain    ${page}    logout.php

Check a wrong password cannot log in
    ${page} =    Log in to Dolibarr    admin    wrong-password
    Should Not Contain    ${page}    logout.php

Check the scheduled jobs run
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user start dolibarr-cron.service
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0

Check a reconfigure without password is accepted
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG}}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be True    ${config['admin_password_set']}

Check a user sync without user domain is rejected
    ${output} =    Run task    module/${module_id}/sync-users    {}
    ...    decode_json=${FALSE}    rc_expected=2
    Should Contain    ${output}    user_domain_required

Take screenshots
    [Tags]    ui
    Import Library    Browser
    New Browser    chromium    headless=True
    New Context    ignoreHTTPSErrors=True
    Login to cluster-admin
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}
    Wait For Elements State    iframe >>> h2 >> text="Status"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/1._Status.png
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=settings
    Wait For Elements State    iframe >>> h2 >> text="Settings"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/2._Settings.png
    Close Browser

Check if dolibarr is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
