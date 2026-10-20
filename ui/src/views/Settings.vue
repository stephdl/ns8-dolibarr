<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row v-if="isRouteMissing">
      <cv-column>
        <NsInlineNotification
          kind="warning"
          :title="$t('settings.no_route_title')"
          :description="$t('settings.no_route_description')"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <!-- web access -->
            <h4 class="mg-bottom-md">{{ $t("settings.web_access") }}</h4>
            <NsTextInput
              :label="$t('settings.dolibarr_fqdn')"
              placeholder="dolibarr.example.org"
              v-model.trim="host"
              class="mg-bottom"
              :invalid-message="$t(error.host)"
              :disabled="stillLoading"
              ref="host"
            />
            <NsToggle
              value="letsEncrypt"
              :label="core.$t('apps_lets_encrypt.request_https_certificate')"
              v-model="isLetsEncryptEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                <div class="mg-bottom-sm">
                  {{ core.$t("apps_lets_encrypt.lets_encrypt_tips") }}
                </div>
                <div class="mg-bottom-sm">
                  <cv-link @click="goToCertificates">
                    {{ core.$t("apps_lets_encrypt.go_to_tls_certificates") }}
                  </cv-link>
                </div>
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <NsInlineNotification
              v-if="isLetsEncryptCurrentlyEnabled && !isLetsEncryptEnabled"
              kind="warning"
              :title="
                core.$t('apps_lets_encrypt.lets_encrypt_disabled_warning')
              "
              :description="
                core.$t(
                  'apps_lets_encrypt.lets_encrypt_disabled_warning_description',
                  {
                    node: status.node_ui_name
                      ? status.node_ui_name
                      : status.node,
                  }
                )
              "
              :showCloseButton="false"
            />
            <NsComboBox
              v-model="language"
              :title="$t('settings.language')"
              :label="$t('settings.choose_language')"
              :options="languageOptions"
              :autoFilter="true"
              :autoHighlight="true"
              :invalid-message="$t(error.language)"
              :disabled="stillLoading"
              :helper-text="$t('settings.language_helper')"
              class="mg-bottom maxwidth"
              ref="language"
            />

            <!-- local administrator -->
            <h4 class="mg-bottom-md mg-top">
              {{ $t("settings.admin_account") }}
            </h4>
            <NsInlineNotification
              kind="info"
              :title="$t('settings.admin_account_info_title')"
              :description="
                isAdminPasswordSet
                  ? $t('settings.admin_account_info_set')
                  : $t('settings.admin_account_info_first')
              "
              :showCloseButton="false"
            />
            <NsToggle
              v-if="isAdminPasswordSet"
              key="changeAdminPassword"
              value="changeAdminPassword"
              :label="$t('settings.change_admin_password')"
              v-model="isChangePassword"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <NsPasswordInput
              v-if="isPasswordActive"
              key="adminPassword"
              v-model="adminPassword"
              :newPasswordLabel="$t('settings.admin_password')"
              :confirmPasswordLabel="$t('settings.admin_password_confirm')"
              :newPasswordInvalidMessage="$t(error.admin_password)"
              :confirmPasswordInvalidMessage="$t(error.admin_password_confirm)"
              :passwordHideLabel="core.$t('password.hide_password')"
              :passwordShowLabel="core.$t('password.show_password')"
              :lengthLabel="core.$t('password.long_enough')"
              :lowercaseLabel="core.$t('password.lowercase_letter')"
              :uppercaseLabel="core.$t('password.uppercase_letter')"
              :numberLabel="core.$t('password.number')"
              :symbolLabel="core.$t('password.symbol')"
              :equalLabel="core.$t('password.equal')"
              :focus="focusPasswordField"
              :minLength="8"
              :disabled="stillLoading"
              @passwordValidation="onAdminPasswordValidation"
              class="mg-bottom maxwidth"
            />

            <!-- authentication -->
            <h4 class="mg-bottom-md mg-top">
              {{ $t("settings.authentication") }}
            </h4>
            <NsInlineNotification
              v-if="!loading.getConfiguration && !userDomainOptions.length"
              kind="info"
              :title="$t('settings.no_user_domain_title')"
              :description="$t('settings.no_user_domain_description')"
              :actionLabel="$t('settings.go_to_domains')"
              @action="goToDomains"
              :showCloseButton="false"
            />
            <template v-else>
              <NsToggle
                value="ldapEnabled"
                :label="$t('settings.ldap_authentication')"
                v-model="isLdapEnabled"
                :disabled="stillLoading"
                class="mg-bottom"
              >
                <template #tooltip>
                  {{ $t("settings.ldap_authentication_tooltip") }}
                </template>
                <template slot="text-left">{{
                  $t("settings.disabled")
                }}</template>
                <template slot="text-right">{{
                  $t("settings.enabled")
                }}</template>
              </NsToggle>
              <template v-if="isLdapEnabled">
                <NsInlineNotification
                  kind="info"
                  :title="$t('settings.ldap_info_title')"
                  :description="$t('settings.ldap_info_description')"
                  :showCloseButton="false"
                />
                <NsComboBox
                  v-model="userDomain"
                  :title="$t('settings.user_domain')"
                  :label="$t('settings.choose_user_domain')"
                  :options="userDomainOptions"
                  :autoFilter="true"
                  :autoHighlight="true"
                  :invalid-message="$t(error.user_domain)"
                  :disabled="stillLoading"
                  class="mg-bottom maxwidth"
                  ref="user_domain"
                />
                <NsComboBox
                  :key="adminGroupComboKey"
                  v-model="adminGroup"
                  :title="$t('settings.admin_group')"
                  :label="
                    loading.listDomainGroups
                      ? $t('common.loading')
                      : $t('settings.choose_admin_group')
                  "
                  :options="adminGroupOptions"
                  :autoFilter="true"
                  :autoHighlight="true"
                  :invalid-message="$t(error.admin_group)"
                  :helper-text="$t('settings.admin_group_helper')"
                  :disabled="
                    stillLoading || loading.listDomainGroups || !userDomain
                  "
                  class="mg-bottom maxwidth"
                  ref="admin_group"
                />
                <NsInlineNotification
                  v-if="error.listDomainGroups"
                  kind="error"
                  :title="$t('action.list-domain-groups')"
                  :description="error.listDomainGroups"
                  :showCloseButton="false"
                />
                <NsToggle
                  value="ldapSync"
                  :label="$t('settings.ldap_sync')"
                  v-model="isLdapSyncEnabled"
                  :disabled="stillLoading"
                  class="mg-bottom"
                >
                  <template #tooltip>
                    {{ $t("settings.ldap_sync_tooltip") }}
                  </template>
                  <template slot="text-left">{{
                    $t("settings.disabled")
                  }}</template>
                  <template slot="text-right">{{
                    $t("settings.enabled")
                  }}</template>
                </NsToggle>
              </template>
            </template>

            <!-- notifications -->
            <h4 class="mg-bottom-md mg-top">
              {{ $t("settings.notifications") }}
            </h4>
            <NsInlineNotification
              v-if="!loading.getConfiguration && !smarthost.enabled"
              kind="warning"
              :title="$t('settings.smarthost_disabled_title')"
              :description="$t('settings.smarthost_disabled_description')"
              :actionLabel="$t('settings.go_to_smarthost')"
              @action="goToSmarthost"
              :showCloseButton="false"
            />
            <NsInlineNotification
              v-if="!loading.getConfiguration && smarthost.enabled"
              kind="info"
              :title="$t('settings.smarthost_enabled_title')"
              :description="
                $t('settings.smarthost_enabled_description', {
                  host: smarthost.host,
                })
              "
              :showCloseButton="false"
            />
            <NsTextInput
              :label="$t('settings.mail_from')"
              :placeholder="mailFromPlaceholder"
              v-model.trim="mailFrom"
              :helper-text="$t('settings.mail_from_helper')"
              :invalid-message="$t(error.mail_from)"
              :disabled="stillLoading"
              class="mg-bottom maxwidth"
              ref="mail_from"
            />

            <NsInlineNotification
              v-if="error.configureModule"
              kind="error"
              :title="$t('action.configure-module')"
              :description="error.configureModule"
              :showCloseButton="false"
            />
            <NsInlineNotification
              v-if="error.getStatus"
              kind="error"
              :title="$t('action.get-status')"
              :description="error.getStatus"
              :showCloseButton="false"
            />
            <NsInlineNotification
              v-if="validationErrorDetails.length"
              kind="error"
              :title="core.$t('apps_lets_encrypt.cannot_obtain_certificate')"
              :showCloseButton="false"
            >
              <template #description>
                <div class="flex flex-col gap-2">
                  <div
                    v-for="(detail, index) in validationErrorDetails"
                    :key="index"
                  >
                    {{ detail }}
                  </div>
                </div>
              </template>
            </NsInlineNotification>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="stillLoading"
              >{{ $t("settings.save") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

const LANGUAGES = {
  auto: "",
  en_US: "English (United States)",
  en_GB: "English (United Kingdom)",
  fr_FR: "Français",
  it_IT: "Italiano",
  de_DE: "Deutsch",
  es_ES: "Español",
  pt_PT: "Português",
  pt_BR: "Português do Brasil",
  eu_ES: "Euskara",
  nl_NL: "Nederlands",
};

export default {
  name: "Settings",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      status: {},
      validationErrorDetails: [],
      urlCheckInterval: null,
      host: "",
      configuredHost: "",
      isLetsEncryptEnabled: false,
      isLetsEncryptCurrentlyEnabled: false,
      isRouteConfigured: true,
      // empty until the configuration loads: NsComboBox shows the label only when the value changes
      language: "",
      adminPassword: "",
      isAdminPasswordSet: false,
      isChangePassword: false,
      adminPasswordValidation: null,
      focusPasswordField: { element: "" },
      isLdapEnabled: false,
      userDomain: "",
      userDomains: [],
      adminGroup: "",
      domainGroups: [],
      adminGroupComboKey: 0,
      isLdapSyncEnabled: true,
      smarthost: { enabled: false, host: "" },
      mailFrom: "",
      loading: {
        getConfiguration: false,
        configureModule: false,
        getStatus: false,
        listDomainGroups: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        getStatus: "",
        listDomainGroups: "",
        host: "",
        lets_encrypt: "",
        language: "",
        admin_password: "",
        admin_password_confirm: "",
        user_domain: "",
        admin_group: "",
        ldap_sync: "",
        mail_from: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    stillLoading() {
      return (
        this.loading.getConfiguration ||
        this.loading.configureModule ||
        this.loading.getStatus
      );
    },
    isPasswordActive() {
      // before the configuration loads every instance looks unconfigured
      if (this.loading.getConfiguration) {
        return false;
      }
      return !this.isAdminPasswordSet || this.isChangePassword;
    },
    isRouteMissing() {
      // a first configuration has no route yet: only a saved host without route means a clone
      return (
        !this.loading.getConfiguration &&
        this.configuredHost &&
        !this.isRouteConfigured
      );
    },
    languageOptions() {
      return Object.entries(LANGUAGES).map(([value, label]) => ({
        name: value,
        // auto follows the browser of each user, its label is translated
        label: label || this.$t("settings.language_auto"),
        value,
      }));
    },
    userDomainOptions() {
      return this.userDomains.map((domain) => ({
        name: domain,
        label: domain,
        value: domain,
      }));
    },
    adminGroupOptions() {
      // keep the saved group selectable even if the list cannot be loaded
      const groups = new Set(this.domainGroups);
      if (this.adminGroup) {
        groups.add(this.adminGroup);
      }
      return [...groups].sort().map((group) => ({
        name: group,
        label: group,
        value: group,
      }));
    },
    mailFromPlaceholder() {
      return "noreply@" + (this.host || "dolibarr.example.org");
    },
  },
  watch: {
    adminPassword() {
      this.error.admin_password = "";
      this.error.admin_password_confirm = "";
    },
    isChangePassword() {
      this.adminPassword = "";
      this.error.admin_password = "";
      this.error.admin_password_confirm = "";
    },
    userDomain(newDomain, oldDomain) {
      if (newDomain === oldDomain) {
        return;
      }
      if (oldDomain) {
        this.adminGroup = "";
      }
      this.listDomainGroups();
    },
  },
  created() {
    this.getConfiguration();
    this.getStatus();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  methods: {
    goToCertificates() {
      this.core.$router.push("/settings/tls-certificates");
    },
    goToSmarthost() {
      this.core.$router.push("/settings/smarthost");
    },
    goToDomains() {
      this.core.$router.push("/domains");
    },
    onAdminPasswordValidation(validation) {
      this.adminPasswordValidation = validation;
    },
    async getStatus() {
      this.loading.getStatus = true;
      this.error.getStatus = "";
      const taskAction = "get-status";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getStatusAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getStatusCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getStatus = this.getErrorMessage(err);
        this.loading.getStatus = false;
        return;
      }
    },
    getStatusAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getStatus = this.$t("error.generic_error");
      this.loading.getStatus = false;
    },
    getStatusCompleted(taskContext, taskResult) {
      this.status = taskResult.output;
      this.loading.getStatus = false;
    },
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
        return;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    getConfigurationCompleted(taskContext, taskResult) {
      const config = taskResult.output;
      this.host = config.host;
      this.configuredHost = config.host;
      this.isLetsEncryptEnabled = config.lets_encrypt;
      this.isLetsEncryptCurrentlyEnabled = config.lets_encrypt;
      this.isRouteConfigured = config.route_configured;
      this.language = config.language;
      this.isAdminPasswordSet = config.admin_password_set;
      this.userDomains = config.user_domains_list;
      // a deleted domain would block every save, show it as disabled
      const hasDomain = config.user_domains_list.includes(config.user_domain);
      this.isLdapEnabled = hasDomain;
      // the admin group must be set before the domain watcher fires
      this.adminGroup = config.admin_group;
      this.userDomain = hasDomain ? config.user_domain : "";
      this.isLdapSyncEnabled = hasDomain ? config.ldap_sync : true;
      this.smarthost = config.smarthost;
      this.mailFrom = config.mail_from;
      this.isChangePassword = false;
      this.adminPassword = "";

      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    async listDomainGroups() {
      this.domainGroups = [];
      this.error.listDomainGroups = "";
      if (!this.userDomain) {
        return;
      }
      this.loading.listDomainGroups = true;
      const taskAction = "list-domain-groups";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.listDomainGroupsAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.listDomainGroupsCompleted
      );
      const res = await to(
        this.createClusterTaskForApp({
          action: taskAction,
          data: { domain: this.userDomain },
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.listDomainGroups = this.getErrorMessage(err);
        this.loading.listDomainGroups = false;
        return;
      }
    },
    listDomainGroupsAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.listDomainGroups = this.$t("error.generic_error");
      this.loading.listDomainGroups = false;
    },
    listDomainGroupsCompleted(taskContext, taskResult) {
      // ignore a late answer for a domain that is no longer selected
      if (taskContext.data.domain !== this.userDomain) {
        return;
      }
      this.domainGroups = taskResult.output.groups.map((g) => g.group);
      // NsComboBox does not refresh its selection when options change
      this.adminGroupComboKey++;
      this.loading.listDomainGroups = false;
    },
    validateConfigureModule() {
      this.clearErrors(this);
      this.validationErrorDetails = [];
      let isValidationOk = true;

      const fail = (field, message, focus = true) => {
        this.error[field] = message;
        if (isValidationOk && focus) {
          this.focusElement(field);
        }
        isValidationOk = false;
      };

      if (!this.host) {
        fail("host", "common.required");
      }
      if (!this.language) {
        fail("language", "common.required");
      }
      if (this.isPasswordActive) {
        const v = this.adminPasswordValidation;
        const isStrong =
          v &&
          v.isLengthOk &&
          v.isLowercaseOk &&
          v.isUppercaseOk &&
          v.isNumberOk &&
          v.isSymbolOk;
        if (!isStrong) {
          fail("admin_password", "settings.admin_password_too_weak", false);
          this.focusPasswordField = { element: "newPassword" };
        } else if (!v.isEqualOk) {
          fail(
            "admin_password_confirm",
            "settings.admin_password_mismatch",
            false
          );
          this.focusPasswordField = { element: "confirmPassword" };
        }
      }
      if (this.isLdapEnabled && !this.userDomain) {
        fail("user_domain", "common.required");
      }
      return isValidationOk;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;
      for (const validationError of validationErrors) {
        const param = validationError.parameter;
        if (validationError.details) {
          this.validationErrorDetails = validationError.details
            .split("\n")
            .filter((detail) => detail.trim() !== "");
        } else {
          this.error[param] = this.$t("settings." + validationError.error);
          if (!focusAlreadySet) {
            if (param === "admin_password") {
              this.focusPasswordField = { element: "newPassword" };
            } else {
              this.focusElement(param);
            }
            focusAlreadySet = true;
          }
        }
      }
    },
    async configureModule() {
      if (!this.validateConfigureModule()) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "configure-module";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );

      const ldap = this.isLdapEnabled;
      const data = {
        host: this.host,
        lets_encrypt: this.isLetsEncryptEnabled,
        language: this.language,
        user_domain: ldap ? this.userDomain : "",
        admin_group: ldap ? this.adminGroup || "" : "",
        ldap_sync: ldap && this.isLdapSyncEnabled,
        mail_from: this.mailFrom,
      };
      if (this.isPasswordActive) {
        data.admin_password = this.adminPassword;
      }

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data,
          extra: {
            title: this.$t("settings.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("settings.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
        return;
      }
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    configureModuleCompleted() {
      this.loading.configureModule = false;
      this.getConfiguration();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";
.mg-bottom {
  margin-bottom: $spacing-06;
}

.mg-bottom-md {
  margin-bottom: $spacing-05;
}

.mg-top {
  margin-top: $spacing-07;
}

.maxwidth {
  max-width: 38rem;
}
</style>
