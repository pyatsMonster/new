# UC Visir Firewall Compliance - CMDB Update

> Créée par **TotalEnergies CES Team** • Dernière mise à jour le **27 janvier 2026** • ~5 min de lecture

---

## Purpose

| Purpose | In Scope | Out of Scope |
|---------|----------|--------------|
| **The purpose of this automation is to update and synchronize firewall Configuration Items (CIs) in ServiceNow CMDB automatically using Ansible.** | • Pre-check of CI existence in ServiceNow CMDB | • Fields that dont exist in the update_cmdb role |
| • Its purpose is to ensure data consistency between network equipment and the CMDB, reducing manual effort and human errors. | • Automatic creation of new CIs if not existing | |
| • Type of automation: **Recurring compliance activity** | • Update of existing CIs with enforced/default values | |
| • **Gain expected:** | • Support for F5, F5 LB, FortiGate, and Palo Alto devices | |
| &nbsp;&nbsp;○ Save several hours of manual CMDB updates per device batch | • Template-driven standardization of CI attributes | |
| &nbsp;&nbsp;○ Improve reliability through template-driven standardization | • Integration with ServiceNow ITSM | |
| &nbsp;&nbsp;○ Enhance traceability with audit logs and ServiceNow integration | • Dynamic inventory creation from devices_list | |
| | • Location and environment management | |

---

## Implementation

| Implementation Details | Tracking |
|------------------------|----------|
| | **SRD:** \<SRD Number\> |
| | **CHG:** \<CHG Number\> |
| | **Schedule:** On-demand / Scheduled |
| | **Ease:** Medium |

---

## Status

| Status | Validation Date | Validated by (Esprit) | Validated by (TotalEnergies) |
|--------|-----------------|----------------------|------------------------------|
| PrePROD | | | |

---

## Prerequisites

| Ansible Collection | Python Modules | Ansible Credentials | AWS/Azure |
|-------------------|----------------|---------------------|-----------|
| servicenow.itsm |  | [TOTAL_CES] SNOW INT.oauth | N/A |
| tte.common.update_cmdb_ci | | [TOTAL_CES] SNOW INT.oauth | N/A |


---

## Inputs

Inputs required by this automation.

| Parameter | Description |
|-----------|-------------|
| **[Asked For each Execution]** | **[Asked For each Execution]** |
| `devices_list` | List of devices to process (YAML/JSON format) |
| `device.name` | CI name in ServiceNow CMDB (required) |
| `device.device_type` | Equipment type: `f5`, `f5lb`, `fortigate`, `paloalto` (required) |
| `device.serial` | Serial number of the device |
| `device.version` | Firmware version |
| `device.model` | Hardware model |
| `device.ip` | Administration IP address |
| `device.manufacturer` | Manufacturer (F5, FORTINET, PALOALTO) |
| `device.mode` | Processing mode: `enforced`, `default` or(auto-detected if absent) |

| **[Set in AAP model variables]** | **[Set in AAP model variables]** |
| `SN_HOST` | ServiceNow instance URL |
| `SN_USERNAME` | ServiceNow API username |
| `SN_PASSWORD` | ServiceNow API password |

---

## Outputs

Outputs generated for this automation.

| Parameter | Description |
|-----------|-------------|
| ServiceNow CMDB | CI Created/Updated |
| Ansible Logs | Execution report: csv, json |

---

## Dependencies/Interactions

List the dependencies or interaction with different components.

> (ex: if updating a CI, you need to ensure proper authentication and network access to ServiceNow)

- [x] CMDB (Create/Update CI)

---

## Process Flow

The following points describe the stepwise activities that are performed in the playbook:

The automation process follows a two-play architecture with dynamic inventory:

### 1. Dynamic Inventory Creation (Play 1 - localhost)

- Validate that `devices_list` is defined and not empty
- Create dynamic inventory by adding each device as a host in `cmdb_devices` group
- Each host receives `device` and `device_type` variables from input
- Display count of created hosts for validation

### 2. CMDB Processing (Play 2 - cmdb_devices)

For each device in the dynamic inventory, the `templater` role executes:

#### 2.1 Pre-check Phase

- Retrieve CI information from ServiceNow CMDB using `servicenow.itsm.configuration_item_info`
- Build list of empty fields in existing CI (`empty_in_ci`)
- Determine processing mode:
  - `enforced` if CI exists in CMDB
  - `default` if CI doesn't exist (new device)

#### 2.2 Template Selection & Rendering

- Select appropriate template based on `device_type`:
  - `f5` → `templates/f5_template.yml.j2`
  - `f5lb` → `templates/f5_lb_template.yml.j2`
  - `fortigate` → `templates/fortigate_template.yml.j2`
  - `paloalto` → `templates/paloalto_template.yml.j2`
- Render Jinja2 template with device data
- Apply **enforced_vars** (always applied):
  - `serial_number`, `u_firmware_version`, `model_id`, `ip_address`, `firmware_manufacturer`, `u_administrated_by`, `category`, `subcategory`
- Apply **default_vars** (conditionally applied):
  - **Mode "default"** (creation): All default values applied
  - **Mode "enforced"** (update): Only applied if field is empty in CMDB
  - Includes: `install_status`, `u_service_class`, `u_used_for`, `company`, `support_group`, `location`
- **Manual mode** (no mode specified): Apply `device.manual_template` if provided

#### 2.3 CMDB Update Phase

- Convert rendered YAML to dictionary
- Prepare variables for CMDB role (`update_cmdb_ci_*`):
  - `update_cmdb_ci_name`, `update_cmdb_ci_serial_number`, `update_cmdb_ci_version_full`
  - `update_cmdb_ci_hardware_model`, `update_cmdb_ci_firmware_manufacturer`
  - `update_cmdb_ci_company`, `update_cmdb_ci_install_status`
  - `update_cmdb_ci_administrated_by`, `update_cmdb_ci_support_group`
  - `update_cmdb_ci_category`, `update_cmdb_ci_subcategory`
  - `update_cmdb_ci_net` (with ADMINISTRATION IP)
  - `update_cmdb_ci_location`, `update_cmdb_ci_environment`
  - `update_cmdb_ci_sys_class_name: cmdb_ci_netgear`
- Set `update_cmdb_ci_create: true` if CI doesn't exist
- Call `tte.common.update_cmdb_ci` role to create/update CI in ServiceNow

---

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              INPUT: devices_list                                │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  PLAY 1: Create Dynamic Inventory (localhost)                                   │
│  • Validate devices_list is defined and not empty                               │
│  • Add each device to cmdb_devices group via add_host                           │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  PLAY 2: Process each host in cmdb_devices (templater role)                     │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  STEP 1: Retrieve CI from ServiceNow                                            │
│  • API call: servicenow.itsm.configuration_item_info                            │
│  • Search by inventory_hostname (device name)                                   │
│  • Build list of empty fields (empty_in_ci)                                     │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │                   │                   │
                    ▼                   ▼                   ▼
        ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
        │   CI EXISTS       │ │   CI DOESN'T EXIST│ │   device.mode     │
        │   records > 0     │ │   records = 0     │ │   is specified    │
        └───────────────────┘ └───────────────────┘ └───────────────────┘
                    │                   │                   │
                    ▼                   ▼                   ▼
        ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
        │ mode = "enforced" │ │ mode = "default"  │ │ mode = device.mode│
        └───────────────────┘ └───────────────────┘ └───────────────────┘
                    │                   │                   │
                    └───────────────────┼───────────────────┘
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  STEP 2: Select Template based on device_type                                   │
│  • f5       → f5_template.yml.j2                                                │
│  • f5lb     → f5_lb_template.yml.j2                                             │
│  • fortigate→ fortigate_template.yml.j2                                         │
│  • paloalto → paloalto_template.yml.j2                                          │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  STEP 3: Render Template (Jinja2)                                               │
│  • enforced_vars: ALWAYS applied (serial, version, model, ip, manufacturer...)  │
│  • default_vars: Applied based on mode (install_status, location, company...)   │
│  • manual_template: Applied if mode is empty and manual_template is defined     │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  STEP 4: Prepare update_cmdb_ci_* variables                                     │
│  • Map rendered values to role variables                                        │
│  • Set update_cmdb_ci_create: true if CI doesn't exist                          │
│  • Set update_cmdb_ci_sys_class_name: cmdb_ci_netgear                           │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  STEP 5: Call tte.common.update_cmdb_ci role                                    │
│  • Create or update CI in ServiceNow CMDB                                       │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
                    ┌───────────────────────────────────────┐
                    │        ✓ CI created/updated           │
                    │         → next host in inventory      │
                    └───────────────────────────────────────┘
```

---

## Exit Scenarios

| Success | Warning | Failure |
|---------|---------|---------|
| All the defined steps are performed successfully, and the firewall CI is successfully created or updated in ServiceNow CMDB. The device information is synchronized with the CMDB. | Partial completion - some devices may have been skipped due to missing required fields (name, device_type). | Failure in one or more tasks leads to ansible playbook not getting executed due to infrastructure issues (ServiceNow API unavailable, authentication failure, network connectivity issues). |

---

## References

Add any link or attach document that can help to understand the use case.

| Document Name | Link |
|---------------|------|
| ServiceNow CMDB API Guide | [ServiceNow Developer Documentation](https://developer.servicenow.com/dev.do#!/reference/api/tokyo/rest/c_TableAPI) |
| TTE Common Collection | Internal Documentation |
| Ansible Automation Platform | [AAP Documentation](https://docs.ansible.com/automation-controller/latest/html/userguide/index.html) |

---

