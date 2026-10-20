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

Log in to Dolibarr
    [Arguments]    ${user}    ${password}
    # The login form needs the session cookie and the CSRF token of the first GET
    ${page} =    Execute Command
    ...    jar=$(mktemp); url=https://${TEST_HOST}; opt="-sk -c $jar -b $jar --resolve ${TEST_HOST}:443:127.0.0.1"; token=$(curl $opt $url/ | sed -n 's/.*name="token" value="\\([^"]*\\)".*/\\1/p' | head -1); curl $opt -L --data-urlencode "token=$token" --data-urlencode 'actionlogin=login' --data-urlencode 'loginfunction=loginfunction' --data-urlencode 'username=${user}' --data-urlencode 'password=${password}' $url/index.php; rm -f $jar
    RETURN    ${page}

*** Test Cases ***
Check if dolibarr is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Suite Variable    ${module_id}    ${output.module_id}

Check the fresh configuration
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Not Be True    ${config['admin_password_set']}

Check a missing admin password is rejected
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
