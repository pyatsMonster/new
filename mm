- name: Define FortiManager target device name (cluster-aware)
  ansible.builtin.set_fact:
    fortimanager_device_name: >-
      {{
        (
          hostvars[inventory_hostname].fmgr_device_name
          | default(inventory_hostname)
        ) | trim
      }}

### GET DEVICE INFORMATION FROM FORTIMANAGER
- name: Get FortiGate detailed information
  environment:
    NO_PROXY: "*"
    no_proxy: "*"
  uri:
    url: "https://{{ FORTI_HOST }}/jsonrpc"
    method: POST
    validate_certs: no
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ FORTI_TOKEN }}"
    body_format: json
    body:
      id: 3
      method: "get"
      params:
        - url: "/dvmdb/adom/{{ adom | default('root') }}/device/{{ fortimanager_device_name }}"
          data:
            adom: "{{ adom | default('root') }}"
  register: fortigate
  delegate_to: localhost
  ignore_errors: no
  when: 
    - FORTI_TOKEN is defined

## - name: Show raw API response
#   debug:
#     var: fortigate.json.result[0].data
#   when: fortigate is defined and fortigate.json is defined

### PROCESS DEVICE DATA
- name: Process FortiGate device data
  vars:
    device_data: "{{ fortigate.json.result[0].data }}"
    ha_slaves: "{{ device_data.ha_slave | default([], true) }}"
    is_cluster: "{{ ha_slaves is not none and ha_slaves | length > 0 }}"
  block:
    ### STANDALONE DEVICE
    - name: Process FortiGate device data
      vars:
        device_data: "{{ fortigate.json.result[0].data }}"
        ha_slaves: "{{ device_data.ha_slave | default([], true) }}"
        is_cluster: "{{ ha_slaves is not none and ha_slaves | length > 0 }}"
      block:
        - name: Enrich CSV host from FortiManager (standalone) - add_host
          vars:
            fortinet_model: >-
              {{
                'FORTINET ' ~
                (
                  device_data.platform_str
                  | regex_replace('^FortiGate-VM', 'VM')
                  | regex_replace('^FortiGate-', 'FortiGATE ')
                  | regex_replace('^FortiGate', 'FortiGATE')
                )
              }}
          ansible.builtin.add_host:
            ansible_host: "{{ device_data.ip | default(omit) }}"
            device_type: "fortigate"
            firmware_manufacturer: "FORTINET"
            groups: "{{ hostvars[inventory_hostname].group_names | default([]) }}"
            ip_address: "{{ device_data.ip | default('') }}"
            model_id: "{{ fortinet_model }}"
            name: "{{ device_data.hostname | default(device_data.name) }}"
            serial_number: "{{ device_data.sn | default('') }}"
            u_firmware_version: >-
              {{
                'FORTINET FortiOS ' ~
                (device_data.os_ver | default('7')) ~ '.' ~
                (device_data.mr | default(0)) ~ '.' ~
                (device_data.patch | default(0))
              }}
            vendor: "FORTINET"
            # Métadonnées FortiManager (optionnel mais utile)
            fortimanager_device_name: "{{ device_data.name | default('') }}"
            fortimanager_adom: "{{ adom | default('') }}"
          delegate_to: localhost
          when:
            - not is_cluster
            - '"FortiGate" in (device_data.platform_str | default(""))'

        - name: Enrich CSV hosts from FortiManager (cluster members) - add_host
          vars:
            fortinet_model: >-
              {{
                'FORTINET ' ~
                (
                  device_data.platform_str
                  | regex_replace('^FortiGate-VM', 'VM')
                  | regex_replace('^FortiGate-', 'FortiGATE ')
                  | regex_replace('^FortiGate', 'FortiGATE')
                )
              }}
            _ha_role: "{{ 'master' if (member.role | default(0) | int) == 0 else 'slave' }}"
            current_ip: "{{ hostvars[member.name].ip_address | default('') | trim }}"
          ansible.builtin.add_host:
            name: "{{ member.name }}"

            # Préserve l’identitée (comme pour F5 / standalone)
            groups: >-
              {{
                hostvars[member.name].group_names
                | default(hostvars[inventory_hostname].group_names | default([]))
              }}
            # type: "{{ hostvars[member.name].type | default('fortinet') }}"

            # Champs “rôle-owned” au format CMDB
            device_type: "fortigate"
            firmware_manufacturer: "FORTINET"
            vendor: "FORTINET"

            serial_number: "{{ member.sn | default('') }}"
            model_id: "{{ fortinet_model }}"
            u_firmware_version: >-
              {{
                'FORTINET FortiOS ' ~
                (device_data.os_ver | default('7')) ~ '.' ~
                (device_data.mr | default(0)) ~ '.' ~
                (device_data.patch | default(0))
              }}

            # IP member : conserve celle déjà connue (CSV/dyn) ; sinon vide.
            ip_address: "{{ current_ip }}"
            # ansible_host: "{{ current_ip if current_ip != '' else omit }}"

            # Métadonnées cluster (comme ton ancien modèle)
            ha_role: "{{ _ha_role }}"
            vip_address: "{{ device_data.ip | default('') }}"

            # Métadonnées FortiManager (optionnel mais utile)
            fortimanager_device_name: "{{ device_data.name | default('') }}"
            fortimanager_adom: "{{ adom | default('') }}"
          loop: "{{ ha_slaves | default([]) }}"
          loop_control:
            loop_var: member
          delegate_to: localhost
          when:
            - is_cluster
            - '"FortiGate" in (device_data.platform_str | default(""))'
            - member.name is defined
            # super important : n’enrichir QUE ce qui est dans tes targets (CSV/dyn), sinon tu recrées 600 hosts
            - member.name in hostvars

    # - name: Create device entries (cluster members) - CLEAN merge with CSV fields
    #   vars:
    #     csv_fields: "{{ hostvars[inventory_hostname].csv_fields | default({}) }}"
    #     fortinet_model: >-
    #       {{
    #         'FORTINET ' ~
    #         (
    #           device_data.platform_str
    #           | regex_replace('^FortiGate-VM', 'VM')
    #           | regex_replace('^FortiGate-', 'FortiGATE ')
    #           | regex_replace('^FortiGate', 'FortiGATE')
    #         )
    #       }}
    #     cluster_devices: >-
    #       {%- set result = [] -%}
    #       {%- for member in ha_slaves -%}
    #       {%-   set ha_role = 'master' if (member.role | default(0) | int) == 0 else 'slave' -%}
    #       {%-   set _ = result.append(
    #             {
    #               'name': member.name,
    #               'device_type': 'fortigate',
    #               'serial': member.sn | default('N/A'),
    #               'version': 'FORTINET FortiOS ' ~
    #                         (device_data.version | default(0) | string)[0] ~ '.' ~
    #                         (device_data.mr | default(0)) ~ '.' ~
    #                         (device_data.patch | default(0)),
    #               'model': fortinet_model,
    #               'vip_address': device_data.ip | default(''),
    #               'manufacturer': 'Fortinet',
    #               'cluster_name': device_data.name,
    #               'ha_role': ha_role
    #             }
    #             | combine(csv_fields)
    #           ) -%}
    #       {%- endfor -%}
    #       {{ result }}
    #   ansible.builtin.set_fact:
    #     devices_list: "{{ (devices_list | default([])) + cluster_devices }}"
    #   delegate_to: localhost
    #   when:
    #     - is_cluster
    #     - '"FortiGate" in (device_data.platform_str | default(""))'

  when: 
    - fortigate is defined 
    - fortigate.json is defined 
    - fortigate.json.result[0].data is defined

### - name: Show processed devices
#   debug:
#     var: devices_list
#   when: devices_list is defined
























#########################################################################################################


        - name: Authenticate to BackBox server
          environment:
            NO_PROXY: "*"
            no_proxy: "*"
          uri:
            url: "{{ backbox_api_url }}/rest/data/token/api/login?username={{ ansible_user | urlencode }}&password={{ ansible_password | urlencode }}"
            method: GET
            return_content: true
            validate_certs: false
            follow_redirects: all
            status_code: [200]
          register: backbox_auth
          delegate_to: localhost

        - name: Set BackBox authentication credentials
          set_fact:
            backbox_auth_token: "{{ backbox_auth.authorization | default(backbox_auth.auth | default(backbox_auth.json.token | default(backbox_auth.json.auth | default(backbox_auth.content | trim)))) }}"
            backbox_session_cookie: "{{ backbox_auth.cookies_string | default('') }}"

        - name: Get device list from BackBox
          environment:
            NO_PROXY: "*"
            no_proxy: "*"
          uri:
            url: "{{ backbox_api_url }}/rest/data/api/devices"
            method: GET
            headers:
              AUTH: "{{ backbox_auth_token }}"
              Cookie: "{{ backbox_session_cookie }}"
              Accept: "application/json"
            return_content: true
            validate_certs: false
            follow_redirects: all
          register: backbox_devices
          delegate_to: localhost

        - name: Build BackBox device name to ID mapping
          set_fact:
            backbox_device_map: >-
              {%- set result = {} -%}
              {%- set devices = backbox_devices.json | default([]) -%}
              {%- if devices is mapping -%}
                {%- set devices = devices.data | default(devices.devices | default([])) -%}
              {%- endif -%}
              {%- if devices is iterable and devices is not string -%}
                {%- for dev in devices -%}
                  {%- set dev_name = dev.deviceName | default(dev.name | default('')) -%}
                  {%- set dev_id = dev.deviceId | default(dev.id | default(0)) -%}
                  {%- set last_backup = dev.lastBackupId | default(0) -%}
                  {%- if dev_name -%}
                    {%- set _ = result.update({dev_name: {'id': dev_id, 'lastBackupId': last_backup}}) -%}
                  {%- endif -%}
                {%- endfor -%}
              {%- endif -%}
              {{ result }}


        - name: Download cluster member configurations from BackBox
          environment:
            NO_PROXY: "*"
            no_proxy: "*"
          uri:
            url: "{{ backbox_api_url }}/rest/data/download/historyFile/{{ backbox_device_map[item.name].lastBackupId }}/configuration_backup.conf.enc/false/false"
            method: GET
            headers:
              AUTH: "{{ backbox_auth_token }}"
              Cookie: "{{ backbox_session_cookie }}"
              Accept: "*/*"
            return_content: true
            validate_certs: false
            follow_redirects: all
            status_code: [200, 404]
          register: member_configs
          loop: "{{ cluster_members }}"
          loop_control:
            label: "Member {{ item.name }}"
          when: item.name in backbox_device_map and (backbox_device_map[item.name].lastBackupId | default(0) | int) > 0
          delegate_to: localhost
          ignore_errors: true

        ################################################################
        # Parse management-ip from each config and build device entries
        ################################################################
        - name: Parse management IPs and build cluster device entries
          vars:
            fallback_ip: "{{ device_data.ip | default('N/A', true) }}"
            cluster_devices: >-
              {%- set result = [] -%}
              {%- for cfg_result in member_configs.results -%}
                {%- set member = cfg_result.item -%}
                {%- set _cfg = cfg_result.content | default('') if ((cfg_result.skipped | default(false)) != true and (cfg_result.status | default(0)) == 200) else '' -%}
                {%- set _ips = _cfg | regex_findall('set management-ip\\s+(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})') | reject('equalto', '0.0.0.0') | list -%}
                {%- set mgmt_ip = _ips[0] if _ips | length > 0 else fallback_ip -%}
                {%- set _ = result.append({
                      'name': member.name,
                      'device_type': 'fortigate',
                      'serial': member.sn | default('N/A'),
                      'version': 'FORTINET FortiOS ' ~ (device_data.version | default(0) | string)[0] ~ '.' ~ (device_data.mr | default(0) | string) ~ '.' ~ (device_data.patch | default(0) | string),
                      'model': device_data.platform_str | default('N/A'),
                      'ip': mgmt_ip,
                      'manufacturer': 'Fortinet',
                      'cluster_name': device_data.name,
                      'ha_role': member.role
                    }) -%}
              {%- endfor -%}
              {{ result }}
          set_fact:
            devices_list: "{{ cluster_devices }}"

        - name: Report cluster members not found in BackBox
          debug:
            msg: "WARNING: {{ item.name }} not found in BackBox or has no backup - using cluster IP ({{ device_data.ip | default('N/A') }}) as fallback"
          loop: "{{ cluster_members }}"
          loop_control:
            label: "{{ item.name }}"
          when: item.name not in backbox_device_map or (backbox_device_map[item.name].lastBackupId | default(0) | int) == 0


        - name: Logout from BackBox server
          environment:
            NO_PROXY: "*"
            no_proxy: "*"
          uri:
            url: "{{ backbox_api_url }}/rest/data/token/api/logout"
            method: GET
            headers:
              AUTH: "{{ backbox_auth_token }}"
              Cookie: "{{ backbox_session_cookie }}"
            validate_certs: false
            status_code: [200, 302, 204, 401]
          delegate_to: localhost
          ignore_errors: true
          run_once: true






            


