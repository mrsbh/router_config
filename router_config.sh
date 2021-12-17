#!bin/sh

DRYRUN=1
CONFIG_FILE=
CUSTOM_CONF_DIR=/jffs/sm/etc

SETUP_BASIC=0
SETUP_NETWORKING=0
SETUP_STATICLEASE=0
WIRELESS_SETUP_OR_MESSAGE=0 # 1 for setup and 0 for message

DNSMASQ_OPTIONS=
DNSMASQ_CUSTCONF=dnsmasq_custom.conf

#Firewall each command on new line
FIREWALL=

BACKUP_VARIABLES_RISKY="
DD_BOARD
^board
browser_method
^cfe
ct_modules
custom_shutdown_command
^def_
^default_
dist_type
dl_ram_addr
early_startup_command
^et0
^et1
^ezc
generate_key
gozila_action
gpio
^hardware
^is_
^kernel_
lan_default
^lan_hw
^lan_ifname
landevs
manual_boot_nv
misc_io_mode
need_commit
^os_
overclocking
pa0maxpwr
phyid_num
pmon_ver
pppd_pppifname
pppoe_ifname
pppoe_wan_ifname
primary_ifname
probe_blacklist
regulation_domain
rescue
reset_
scratch
sdram
^sh_
^skip
sshd_dss_host_key
sshd_rsa_host_key
startup_command
^wan_default
^wan_hw
^wan_if
^wan_vport
^wandevs
web_hook_libraries
^wifi_
wl0.1_hwaddr
wl0.2_hwaddr
wl0.3_hwaddr
wl0_hwaddr
wl0_ifname
wl0_radioids
wl_hwaddr
wl_ifname
^wlan_
"

while [ -n "$1" ]
do
    if [ "$1" == "-cf" ] && [ -n "$2" ]
    then
        shift
        CONFIG_FILE=$1
        shift
    elif [ "$1" == "-y" ]
    then
        DRYRUN=0
        shift
    elif [ "$1" == "-sb" ]
    then
        SETUP_BASIC=1
        shift
    elif [ "$1" == "-sn" ]
    then
        SETUP_NETWORKING=1
        SETUP_STATICLEASE=1
        shift
    elif [ "$1" == "-ss" ]
    then
        SETUP_STATICLEASE=1
        shift
    elif [ "$1" == "-sf" ]
    then
        SETUP_FIREWALL=1
        shift
    elif [ "$1" == "-b" ]
    then
        BACKUP=1
        shift
    else
        echo "Unknown option $1, ignoring"
        shift
    fi
done

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ] && [ -r "$CONFIG_FILE" ]
then
    . $CONFIG_FILE
else
    echo "Config file not provided or is not readable"
    exit 1
fi
if [ -z "$SUBNETS" ]
then
    echo "Invalid configuration, subnets must be defined"
    exit 1
fi

isNumber() {
    local _in_v=$1
    if expr "$_in_v" : '[0-9][0-9]*$' >/dev/null
    then
        return 0
    fi
    return 1
}

isIPv4() {
    local _in_v=$1
    if expr "$_in_v" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null
    then
        return 0
    fi
    return 1
}

isSubnetPrefix() {
    local _in_v=$1
    if expr "$_in_v" : '[0-9][0-9\.]*$' >/dev/null
    then
        return 0
    fi
    return 1
}

isMac() {
    local _in_v=$1
    if expr "$_in_v" : '[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]$' >/dev/null
    then
        return 0
    fi
    return 1
}

isSubstring() {
    local _is_str="$1"
    local _is_sub="$2"
    case "$_is_str" in
        *"$_is_sub"*) return 0;;
    esac
    return 1
}

rangeToCIDRs() {
    local _rtcs_start=$1
    local _rtcs_end=$2
    local _rtcs_retvar=$3
    local _rtcs_mask=1
    local _rtcs_maskn=32
    local _rtcs_first
    local _rtcs_vals=

    let _rtcs_end=$_rtcs_end+1
    let _rtcs_first=$_rtcs_start+$_rtcs_mask
    while [ $_rtcs_first -le $_rtcs_end ]
    do
        if [ $(($_rtcs_start & $_rtcs_mask)) != 0 ]
        then
            _rtcs_vals="$_rtcs_vals $_rtcs_start/$_rtcs_maskn"
            let _rtcs_start=$_rtcs_start+$_rtcs_mask
        fi
        _rtcs_mask=$(($_rtcs_mask<<1))
        let _rtcs_maskn=$_rtcs_maskn-1
        let _rtcs_first=$_rtcs_start+$_rtcs_mask
    done
    while [ $_rtcs_start -lt $_rtcs_end ]
    do
        _rtcs_mask=$(($_rtcs_mask>>1))
        let _rtcs_maskn=$_rtcs_maskn+1
        if [ $(($_rtcs_end & $_rtcs_mask)) != 0 ]
        then
            _rtcs_vals="$_rtcs_vals $_rtcs_start/$_rtcs_maskn"
            let _rtcs_start=$_rtcs_start+$_rtcs_mask
        fi
    done
    eval "$_rtcs_retvar=\"$_rtcs_vals\""
}

defineSubnets() {
    local _ds_name
    local _ds_pre
    local _ds_if
    local _ds_item
    local _ds_cnt=0
    local _ds_ngcnt=0
    local _ds_all=""
    local _ds_ngall=""
    for _ds_item in $SUBNETS
    do
        if [ -z "$_ds_name" ]
        then
            _ds_name=$_ds_item
        elif [ -z "$_ds_pre" ]
        then
            _ds_pre=$_ds_item
        elif [ -z "$_ds_if" ]
        then
            _ds_if=$_ds_item
            if isSubstring "$_ds_all" "$_ds_name"
            then
                echo "Subnet $_ds_name already defined, will be ignored."
            else
                if isSubnetPrefix $_ds_pre
                then
                    eval "SUBNET_$_ds_name=$_ds_pre"
                    eval "SUBNET_IF_$_ds_name=$_ds_if"
                    _ds_all="$_ds_all $_ds_name"
                    if [ "$_ds_name" != Guest ]
                    then
                        _ds_ngall="$_ds_ngall $_ds_name"
                        let _ds_ngcnt=$_ds_ngcnt+1
                    fi
                    let _ds_cnt=$_ds_cnt+1
                fi
            fi
            _ds_name=
            _ds_pre=
            _ds_if=
        fi
    done
    eval "SUBNETS_ALL=\"$_ds_all\""
    eval "SUBNETS_NONGUEST_ALL=\"$_ds_ngall\""
    eval "SUBNETS_NONGUEST_CNT=$_ds_ngcnt"
    eval "SUBNETS_CNT=$_ds_cnt"
}

getSubnet() {
    local _gs_name=$1
    local _gs_retvar=$2
    eval "$_gs_retvar=\${SUBNET_$_gs_name}.1/24"
}

getSubnetPrefix() {
    local _gsp_name=$1
    local _gsp_retvar=$2
    eval "$_gsp_retvar=\${SUBNET_$_gsp_name}."
}

getSubnetInterface() {
    local _gsi_name=$1
    local _gsi_retvar=$2
    eval "$_gsi_retvar=\${SUBNET_IF_$_gsi_name}"
}

defineSubnetDistribution() {
    local _dsd_type
    local _dsd_start
    local _dsd_end
    local _dsd_item
    local _dsd_cidrs
    local _dsd_cnt=0
    local _dsd_tcnt
    local _dsd_idx
    for _dsd_item in $SUBNET_DISTRIBUTION
    do
        if [ -z "$_dsd_type" ]
        then
            _dsd_type=$_dsd_item
        elif [ -z "$_dsd_start" ]
        then
            _dsd_start=$_dsd_item
        elif [ -z "$_dsd_end" ]
        then
            _dsd_end=$_dsd_item
            if isNumber $_dsd_start && isNumber $_dsd_end
            then
                _dsd_start=$(expr $_dsd_start + 0)
                _dsd_end=$(expr $_dsd_end + 0)
                rangeToCIDRs $_dsd_start $_dsd_end _dsd_cidrs
                #                echo "$_dsd_start-$_dsd_end = $_dsd_cidrs"
                eval "_dsd_tcnt=\${SUBNET_DIST_CNT_$_dsd_type}"
                if [ -z "$_dsd_tcnt" ]
                then
                    _dsd_idx=0
                    _dsd_tcnt=1
                else
                    _dsd_idx=$_dsd_tcnt
                    let _dsd_tcnt=$_dsd_tcnt+1
                fi
                eval "SUBNET_DIST_CNT_$_dsd_type=$_dsd_tcnt"
                eval "SUBNET_DIST_START_${_dsd_type}_I${_dsd_idx}=$_dsd_start"
                eval "SUBNET_DIST_END_${_dsd_type}_I${_dsd_idx}=$_dsd_end"
                eval "SUBNET_DIST_CIDRS_${_dsd_type}_I${_dsd_idx}=\"$_dsd_cidrs\""
                eval "SUBNET_DIST_TYPE_I${_dsd_cnt}=$_dsd_type"
                eval "SUBNET_DIST_START_I${_dsd_cnt}=$_dsd_start"
                eval "SUBNET_DIST_END_I${_dsd_cnt}=$_dsd_end"
                let _dsd_cnt=$_dsd_cnt+1
            fi
            _dsd_type=
            _dsd_start=
            _dsd_end=
        fi
    done
    eval "SUBNET_DIST_CNT=$_dsd_cnt"
}

getSubnetDistributionCount() {
    local _gsdc_type=$1
    local _gsdc_retvar=$2
    eval "$_gsdc_retvar=\${SUBNET_DIST_CNT_$_gsdc_type}"
}

getSubnetDistributionBlock() {
    local _gsdb_type=$1
    local _gsdb_index=$2
    local _gsdb_retvars=$3
    local _gsdb_retvare=$4
    local _gsdb_cnt
    getSubnetDistributionCount "${_gsdb_type}" _gsdb_cnt
    if [ -n "$_gsdb_index" ] && [ $_gsdb_index -lt $_gsdb_cnt ]
    then
        eval "$_gsdb_retvars=\${SUBNET_DIST_START_${_gsdb_type}_I$_gsdb_index}"
        eval "$_gsdb_retvare=\${SUBNET_DIST_END_${_gsdb_type}_I$_gsdb_index}"
    fi
}

getSubnetDistributionCIDRs() {
    local _gsbc_type=$1
    local _gsbc_index=$2
    local _gsbc_retvar=$3
    local _gsbc_cnt
    getSubnetDistributionCount "${_gsbc_type}" _gsbc_cnt
    if [ -n "$_gsbc_index" ] && [ $_gsbc_index -lt $_gsbc_cnt ]
    then
        eval "$_gsbc_retvar=\"\${SUBNET_DIST_CIDRS_${_gsbc_type}_I$_gsbc_index}\""
    fi
}

findStaticLeaseHostTypeByIP() {
    local _fslhtbi_ip=$1
    local _fslhtbi_retvar=$2
    local _fslhtbi_idx=0
    local _fslhtbi_start=0
    local _fslhtbi_end=0
    if [ -n "$_fslhtbi_ip" ] && isNumber $_fslhtbi_ip
    then
        while [ $_fslhtbi_idx -lt $SUBNET_DIST_CNT ]
        do
            eval "_fslhtbi_start=\$SUBNET_DIST_START_I$_fslhtbi_idx"
            eval "_fslhtbi_end=\$SUBNET_DIST_END_I$_fslhtbi_idx"
            if [ $_fslhtbi_ip -ge $_fslhtbi_start ] && [ $_fslhtbi_ip -le $_fslhtbi_end ]
            then
                eval "$_fslhtbi_retvar=\$SUBNET_DIST_TYPE_I$_fslhtbi_idx"
                return
            fi
            let _fslhtbi_idx=$_fslhtbi_idx+1
        done
    fi
}

defineStaticLeases() {
    local _dsl_host
    local _dsl_mac
    local _dsl_sub
    local _dsl_ip
    local _dsl_item
    local _dsl_cnt=0
    local _dsl_type
    local _dsl_total=0
    for _dsl_item in $STATIC_LEASES
    do
        if [ -z "$_dsl_host" ]
        then
            _dsl_host=$_dsl_item
        elif [ -z "$_dsl_mac" ]
        then
            _dsl_mac=$_dsl_item
        elif [ -z "$_dsl_sub" ]
        then
            _dsl_sub=$_dsl_item
        elif [ -z "$_dsl_ip" ]
        then
            _dsl_ip=$_dsl_item
            if isMac $_dsl_mac && isNumber $_dsl_ip
            then
                eval "STATIC_LEASES_I${_dsl_cnt}=$_dsl_host"
                eval "STATIC_LEASES_MAC_${_dsl_host}=$_dsl_mac"
                eval "STATIC_LEASES_IP_${_dsl_host}=$_dsl_ip"
		if [ "$_dsl_sub" == Auto ]
		then
                    findStaticLeaseHostTypeByIP $_dsl_ip _dsl_type
                    if [ "$_dsl_type" == Dynamic ]
                    then
                        echo "Warning: Static lease in dynamic block, $_dsl_ip"
                    fi
                    if [ "$_dsl_type" == Blocked ]
                    then
                        #                    echo Blocked $_dsl_host $SUBNETS_NONGUEST_ALL
                        eval "STATIC_LEASES_SUBNETS_${_dsl_host}=\"$SUBNETS_NONGUEST_ALL\""
                        let _dsl_total=$_dsl_total+$SUBNETS_NONGUEST_CNT
                    elif isSubstring "$WORKSTATIONS" $_dsl_host
                    then
                        #                    echo Workstation $_dsl_host $SUBNETS_ALL
                        eval "STATIC_LEASES_SUBNETS_${_dsl_host}=\"$SUBNETS_ALL\""
                        let _dsl_total=$_dsl_total+$SUBNETS_CNT
                    else
                        #                    echo Normal $_dsl_host Main
                        eval "STATIC_LEASES_SUBNETS_${_dsl_host}=\"Main\""
                        let _dsl_total=$_dsl_total+1
                    fi
                else
                    eval "STATIC_LEASES_SUBNETS_${_dsl_host}=\"$_dsl_sub\""
                    let _dsl_total=$_dsl_total+1
                fi
                let _dsl_cnt=$_dsl_cnt+1
            fi
            _dsl_host=
            _dsl_mac=
            _dsl_sub=
            _dsl_ip=
        fi
    done
    eval "STATIC_LEASES_TOTAL_CNT=$_dsl_total"
    eval "STATIC_LEASES_CNT=$_dsl_cnt"
}

getStaticLeaseHostByIndex() {
    local _gslhbi_idx=$1
    local _gslhbi_retvar=$2
    local _gslhbi_v
    if isNumber $_gslhbi_idx && [ $_gslhbi_idx -lt $STATIC_LEASES_CNT ]
    then
        eval "$_gslhbi_retvar=\$STATIC_LEASES_I$_gslhbi_idx"
    fi
}

getStaticLeaseSubnetsForHost() {
    local _gslsfh_host=$1
    local _gslsfh_retvar=$2
    local _gslsfh_v
    if [ -n "$_gslsfh_host" ]
    then
        eval "$_gslsfh_retvar=\$STATIC_LEASES_SUBNETS_$_gslsfh_host"
    fi
}

getHostIPSuffix() {
    local _ghis_host=$1
    local _ghis_retvar=$2
    local _ghis_v
    eval "_ghis_v=\$STATIC_LEASES_IP_$_ghis_host"
    if [ -z "$_ghis_v" ] && isNumber $_ghis_host
    then
        _ghis_v=$_ghis_host
    fi
    if [ -n "$_ghis_v" ]
    then
        eval "$_ghis_retvar=$_ghis_v"
    fi
}

getHostIPForSubnet() {
    local _ghifs_host=$1
    local _ghifs_subname=$2
    local _ghifs_retvar=$3
    local _ghifs_pre
    local _ghifs_suf
    getSubnetPrefix $_ghifs_subname _ghifs_pre
    getHostIPSuffix $_ghifs_host _ghifs_suf
    eval "$_ghifs_retvar=$_ghifs_pre$_ghifs_suf"
}

getHostIP() {
    getHostIPForSubnet $1 Main $2
}

getHostMac() {
    local _ghm_host=$1
    local _ghm_retvar=$2
    local _ghm_v
    if [ -n "$_ghm_host" ]
    then
        eval "$_ghm_retvar=\$STATIC_LEASES_MAC_$_ghm_host"
    fi
}

setNVRam() {
    if [ "$DRYRUN" == 0 ]
    then
        nvram set $1="$2"
    else
        echo nvram set $1="$2"
    fi
}

# original credit to https://forum.dd-wrt.com/phpBB2/viewtopic.php?t=44324
backupSetup() {
    local _bs_date="$(date +%Y%m%d)"
    local _bs_uniqid="$(nvram get lan_hwaddr)"
    local _bs_dir=/tmp
    local _bs_tempfile=/tmp/tmp.$$
    local _bs_fn
    local _bs_var
    local _bs_value
    local _bs_expr="("

    _bs_uniqid="${_bs_uniqid//:/}"
    _bs_fn="${_bs_uniqid}_${_bs_date}"
    _bs_fnbk="${_bs_fn}.sh"
    _bs_fnrisky="${_bs_fn}_dangerous.sh"

    nvram show 2>/dev/null | grep -E '^[a-zA-Z].*=' | awk -F= '{print $1}' | grep -v "[ /+<>,:;]" | sort -u >$_bs_tempfile
    echo -e "#!/bin/sh\n#\necho \"Write variables\"\n" | tee -i $_bs_dir/$_bs_fnrisky > $_bs_dir/$_bs_fnbk
    for _bs_var in $BACKUP_VARIABLES_RISKY
    do
        _bs_expr="$_bs_expr$_bs_var|"
    done

    cat $_bs_tempfile | while read _bs_var
    do
        if echo $_bs_var | grep -q -E "${_bs_expr}ZZZ)"
        then
            _bs_fn=$_bs_dir/$_bs_fnrisky
        else
            _bs_fn=$_bs_dir/$_bs_fnbk
        fi
        _bs_value="$(nvram get $_bs_var)"
        if [ -z "$_bs_value" ]
        then
            echo -e "nvram set $_bs_var=" >> $_bs_fn
        else
            # write the var to the file and use \ for special chars: (\$`")
            echo -en "nvram set $_bs_var=\"" >> $_bs_fn
            echo -n "$_bs_value" | sed 's/\\/\\\\/g' | sed 's/`/\\`/g' | sed 's/\$/\\\$/g' | sed 's/\"/\\"/g' >> $_bs_fn
            echo -e "\"" >> $_bs_fn
        fi
    done
    rm $_bs_tempfile
    echo -e "\n# Commit variables\necho \"Save variables to nvram\"\nnvram commit" | tee -ia $_bs_dir/$_bs_fnrisky >> $_bs_dir/$_bs_fnbk
    cd $_bs_dir
    chmod +x $_bs_fnbk $_bs_fnrisky
    tar -czf nvram_backup.tar.gz $_bs_fnbk $_bs_fnrisky
    cd - >/dev/null
}

setupBasic() {
    setNVRam ntp_enable 1
    setNVRam time_zone $TIMEZONE

    setNVRam router_name $NAME
    setNVRam wan_hostname $NAME
    setNVRam wan_domain $DOMAINNAME
    SSH_ENABLED=`nvram get sshd_enable`
    if [ "$SSH_ENABLED" == 1 ]
    then
        if [ -n "$SSH_KEY" ]
        then
            setNVRam sshd_authorized_keys "$SSH_KEY"
            setNVRam sshd_passwd_auth 0
        fi
        if [ -n "$SSH_PORT" ] && isNumber $SSH_PORT
        then
            setNVRam sshd_port $SSH_PORT
        fi
    fi

    if [ $WIRELESS_SETUP_OR_MESSAGE == 0 ]
    then
        echo "Setup Wireless:"
        echo "    * On Wireless -> Basic Settings"
        echo "        * Use AP mode with Mixed network mode"
        echo "            * May want to Disable SSID Broadcast"
        echo "            * Check frequencies, sometimes 5GHz is listed before 2GHz"
        echo "    * On Wireless -> Security"
        echo "        * Use WPA2/WPA mode with AES"
        echo "    * Apply settings"
    else
        echo "Not implemented yet"
        # wl_mode=ap
        # wl_net_mode=mixed
        #> wl_ssid=<SSID>
        #> wl_tpc_db=off
        # wl0_mode=ap
        # wl0_net_mode=mixed
        #> wl0_akm=psk psk2
        #> wl0_auth_mode=none
        #> wl0_authmode=open
        #> wl0_closed=1
        #> wl0_security_mode=psk psk2
        #> wl0_ssid=<SSID>
        #> wl0_wpa_psk=<PASSWORD>
        #> wl0_crypto=aes
        #wl0_wds0=*,auto,aes,psk2,<SSID>,<PASSWORD>
        # wl1_mode=ap
        # wl1_net_mode=mixed
        #> wl1_akm=psk psk2
        #> wl1_auth_mode=none
        #> wl1_authmode=open
        #> wl1_closed=1
        #> wl1_security_mode=psk psk2
        #> wl1_ssid=<SSID>
        #> wl1_wpa_psk=<PASSWORD>
        #wl1_wds0=*,auto,aes,psk2,<SSID>,<PASSWORD>
        # wl2_mode=ap
        # wl2_net_mode=mixed
        #> wl2_akm=psk psk2
        #> wl2_auth_mode=none
        #> wl2_authmode=open
        #> wl2_closed=1
        #> wl2_security_mode=psk psk2
        #> wl2_ssid=<SSID>
        #> wl2_wpa_psk=<PASSWORD>
    fi
    if isSubstring "$SUBNETS_ALL" Guest
    then
        if [ $WIRELESS_SETUP_OR_MESSAGE == 0 ]
        then
            echo "Create Guest Network:"
            echo "    * On Wireless -> Basic Settings"
            echo "        * Find the frequency and add Virtual Interface"
            echo "            * May want to Enable AP Isolation (guests cannot see each other)"
            echo "            * Set networking to Unbridged, enable NAT (for Internet access), Net Isolation (guests cannot see nonguests)"
            echo "            * Set IP address and mask"
            echo "    * On Wireless -> Security"
            echo "        * Use WPA2/WPA mode with AES"
            echo "    * Apply settings, wait for 30 seconds for interface to be created"
        else
            echo "Not implemented yet"
            # it did this for guest on wl1
            #> wl1.1_akm=psk psk2
            #> wl1.1_ap_isolate=1
            #> wl1.1_auth=0
            #> wl1.1_auth_mode=none
            #> wl1.1_authmode=open
            #> wl1.1_bridged=0
            #> wl1.1_bss_maxassoc=50
            #> wl1.1_closed=0
            #> wl1.1_crypto=aes
            #> wl1.1_dns_ipaddr=0.0.0.0
            #> wl1.1_dns_redirect=0
            #> wl1.1_gtk_rekey=3600
            #> wl1.1_hwaddr=<MAC_ADDR> - mac addr of wl1 + 1
            #> wl1.1_ifname=wl1.1
            #> wl1.1_ipaddr=<GUEST_SUBNET>.1
            #> wl1.1_isolation=1
            #> wl1.1_key=1
            #> wl1.1_mode=ap
            #> wl1.1_multicast=0
            #> wl1.1_nat=1
            #> wl1.1_netmask=255.255.255.0
            #> wl1.1_radius_ipaddr=0.0.0.0
            #> wl1.1_radius_port=1812
            #> wl1.1_ssid=<SSID>
            #> wl1.1_wep_buf=:::::
            #> wl1.1_wep=disabled
            #> wl1.1_wme=on
            #> wl1.1_wpa_gtk_rekey=3600
            #> wl1.1_wpa_psk=<PASSWORD>
            #> wl1_vifs=wl1.1
            #> wl1X1_security_mode=psk psk2
        fi
        if [ $WIRELESS_SETUP_OR_MESSAGE == 0 ]
        then
            echo "    * On Setup -> Networking"
            echo "        * Might have to reboot for the interface to be created"
            echo "        * Add another DHCPd server for this virtual interface and set starting and ending DHCP addresses"
        else
            echo "Not implemented yet"
            #> mdhcpd_count=1
            #> mdhcpd=wl1.1>On>64>128>1440
        fi
    fi
    if isSubstring "$SUBNETS_ALL" IoT
    then
        if [ $WIRELESS_SETUP_OR_MESSAGE == 0 ]
        then
            echo "Create IoT Network:"
            echo "    * On Wireless -> Basic Settings"
	    echo "        * Find the frequency (prefer 2.4GHz) and add Virtual Interface"
            echo "            * May want to Enable AP Isolation (IoT devices cannot see each other)"
            echo "            * Set networking to Unbridged, enable NAT (for Internet access), Net Isolation (IoT devices cannot see main network)"
            echo "            * Set IP address and mask"
            echo "    * On Wireless -> Security"
            echo "        * Use WPA2/WPA mode with AES"
            echo "    * Apply settings, wait for 30 seconds for interface to be created"
        else
            echo "Not implemented yet"
            # it did this for second vap for IoT
            #> wl1.2_akm=psk psk2
            #> wl1.2_ap_isolate=1
            #> wl1.2_auth=0
            #> wl1.2_auth_mode=none
            #> wl1.2_authmode=open
            #> wl1.2_bridged=0
            #> wl1.2_bss_maxassoc=50
            #> wl1.2_closed=1
            #> wl1.2_crypto=aes
            #> wl1.2_dns_ipaddr=0.0.0.0
            #> wl1.2_dns_redirect=0
            #> wl1.2_gtk_rekey=3600
            #> wl1.2_hwaddr=<MAC_ADDR> - mac addr of wl1 + 2
            #> wl1.2_ifname=wl1.2
            #> wl1.2_ipaddr=<IOT_SUBNET>.1
            #> wl1.2_isolation=1
            #> wl1.2_key=1
            #> wl1.2_mode=ap
            #> wl1.2_multicast=0
            #> wl1.2_nat=1
            #> wl1.2_netmask=255.255.255.0
            #> wl1.2_radius_ipaddr=0.0.0.0
            #> wl1.2_radius_port=1812
            #> wl1.2_ssid=<SSID>
            #> wl1.2_wep_buf=:::::
            #> wl1.2_wep=disabled
            #> wl1.2_wme=on
            #> wl1.2_wpa_gtk_rekey=3600
            #> wl1.2_wpa_psk=<PASSWORD>
            #> wl1_vifs=wl1.1 wl1.2
            #> wl1X2_security_mode=psk psk2
        fi
        if [ $WIRELESS_SETUP_OR_MESSAGE == 0 ]
        then
            echo "    * On Setup -> Networking"
            echo "        * Might have to reboot for the interface to be created"
            echo "        * Add another DHCPd server for this virtual interface and set starting and ending DHCP addresses"
        else
            echo "Not implemented yet"
            #> mdhcpd_count=2
            #> mdhcpd=wl1.1>On>64>128>1440 wl1.2>On>64>128>1440
        fi
    fi

    if [ "$LOGGING" == 1 ]
    then
        setNVRam syslogd_enable 1
        setNVRam klogd_enable 1
        setNVRam log_enable 1
        setNVRam log_dropped 1
    fi

    if [ -n "$REMOTE_MGMT" ]
    then
        port=
        ipstart=
        ipend=
        for item in $REMOTE_MGMT
        do
            if [ -z "$port" ]
            then
                port=$item
            elif [ -z "$ipstart" ]
            then
                ipstart=$item
            else
                ipend=$item
            fi
        done
        if [ -n "$port" ] && isNumber $port
        then
            setNVRam remote_management 1
            setNVRam http_wanport $port
            if [ -n "$ipstart" ] && [ -n "$ipend" ]
            then
                ippre=${ipstart%.*}
                if [ ${ipend#$ippre} != $ipend ]
                then
                    setNVRam remote_ip_any 0
                    setNVRam remote_ip "$ipstart ${ipend#$ippre.}"
                fi
            fi
        fi
    fi
    # for switch Admin/Mgmt
    #    if [ "$AS_SWITCH" == 1 ]
    #> info_passwd=1
}

setupDHCP() {
    cnt=
    getSubnetDistributionCount Dynamic cnt
    if [ -z "$cnt" ] || [ "$cnt" != "1" ]
    then
        echo "There should be one and only one band for dynamic addresses in the subnet, found $cnt."
        exit 1
    fi
    getSubnetDistributionBlock Dynamic 0 DHCP_START DHCP_END
    let DHCP_COUNT=$DHCP_END-$DHCP_START+1

    setNVRam dhcp_start ${MAIN_SUBNET}${DHCP_START}
    setNVRam dhcp_num $DHCP_COUNT
    setNVRam dhcp_lease $DHCP_LEASE
    #    if [ "$AS_SWITCH" == 1 ]
    #> dnsmasq_enable=0
    #> ttraff_enable=0
}

setupDnsmasq() {
    if [ -n "$DNSMASQ_OPTIONS" ]
    then
#        DNSMASQ_OPTIONS="${DNSMASQ_OPTIONS}
#"
        setNVRam dnsmasq_enable 1
        setNVRam auth_dnsmasq 1
        setNVRam dnsmasq_options "${DNSMASQ_OPTIONS}
"
    fi
}

setupDNS() {
    if [ -n "$DNS_SERVER" ] && [ "$DNS_SERVER" != "1" ] && [ "$DNS_SERVER" != "Router" ]
    then
        getHostIPSuffix "$DNS_SERVER" DNS_SERVER_IP_SUFFIX
        findStaticLeaseHostTypeByIP $DNS_SERVER_IP_SUFFIX DNS_IP_TYPE
        if [ "$DNS_IP_TYPE" != Reserved ]
        then
            if [ "$DNS_IP_TYPE" == Dynamic ]
            then
                echo "Error, DNS IP is in Dynamic block $DNS_SERVER_IP_SUFFIX"
            else
                echo "Warning, DNS IP should ideally be in Reserved block $DNS_SERVER_IP_SUFFIX"
            fi
        fi
        getHostIP "$DNS_SERVER" DNS_SERVER_IP
        for subnet in $SUBNETS_ALL
        do
            getSubnetInterface $subnet interface
            getSubnetPrefix $subnet prefix
            DNSMASQ_OPTIONS="${DNSMASQ_OPTIONS}
dhcp-option=${interface},6,${DNS_SERVER_IP},${prefix}1"
        done
        setNVRam dns_dnsmasq 1
        setupDnsmasq
    fi
}

setupStaticLeases() {
    subname=
    ip=
    host=
    mac=
    leases=

    index=0
    while [ $index -lt $STATIC_LEASES_CNT ]
    do
        getStaticLeaseHostByIndex $index host
        subnames=
        getStaticLeaseSubnetsForHost $host subnames
        for subname in $subnames
        do
            getHostMac $host mac
            getHostIPForSubnet $host $subname ip
            leases="${leases}$mac=$host=$ip=$DHCP_LEASE "
            echo "dhcp-host=$mac,$host,$ip,${DHCP_LEASE}m" >> /tmp/$DNSMASQ_CUSTCONF
        done
        let index=$index+1
    done

    if [ $STATIC_LEASES_TOTAL_CNT -gt 50 ] && [ -d $CUSTOM_CONF_DIR ]
    then
        mv /tmp/$DNSMASQ_CUSTCONF $CUSTOM_CONF_DIR/
        DNSMASQ_OPTIONS="${DNSMASQ_OPTIONS}
conf-file=$CUSTOM_CONF_DIR/$DNSMASQ_CUSTCONF"
        setupDnsmasq
    else
        setNVRam static_leasenum $STATIC_LEASES_TOTAL_CNT
        setNVRam static_leases "${leases}"
    fi
}

setupFirewall() {
    # block devices in Blocked ranges from Main subnet, in case they connect to Main subnet
    getSubnetDistributionCount Blocked count
    index=0
    while [ $index -lt $count ]
    do
        getSubnetDistributionCIDRs Blocked $index cidrs
        for cidr in $cidrs
        do
            FIREWALL="$FIREWALL
iptables -I FORWARD -s ${MAIN_SUBNET}$cidr -j logdrop"
        done
        let index=$index+1
    done
    # if IoT subnet exists, block everything from it except for AllowedIoT block
    if [ -n "$IOT_IF" ]
    then
        FIREWALL="$FIREWALL
iptables -I FORWARD -i ${IOT_IF} -j logdrop"
        count=0
        getSubnetDistributionCount AllowedIoT count
        index=0
        while [ $index -lt $count ]
        do
            getSubnetDistributionCIDRs AllowedIoT $index cidrs
            for cidr in $cidrs
            do
                FIREWALL="$FIREWALL
iptables -I FORWARD -i ${IOT_IF} -s ${IOT_SUBNET}$cidr -j logaccept
iptables -I FORWARD -i ${IOT_IF} -o ${GUEST_IF} -s ${IOT_SUBNET}$cidr -j logdrop
iptables -I FORWARD -i ${IOT_IF} -o br0 -s ${IOT_SUBNET}$cidr -j logdrop"
            done
            let index=$index+1
        done
    fi
    # allow DNS
    if [ -n "$DNS_SERVER_IP" ]
    then
        if [ -n "$GUEST_IF" ]
        then
            # allow DNS and BOOTPS from guest network
            FIREWALL="${FIREWALL}
iptables -I FORWARD -i ${GUEST_IF} -p tcp -d ${DNS_SERVER_IP} -m multiport --dports 53,67 -j ACCEPT
iptables -I FORWARD -i ${GUEST_IF} -p udp -d ${DNS_SERVER_IP} -m multiport --dports 53,67 -j ACCEPT"
        fi
        if [ -n "$IOT_IF" ]
        then
            # allow DNS and BOOTPS from IoT network
            FIREWALL="${FIREWALL}
iptables -I FORWARD -i ${IOT_IF} -p tcp -d ${DNS_SERVER_IP} -m multiport --dports 53,67 -j ACCEPT
iptables -I FORWARD -i ${IOT_IF} -p udp -d ${DNS_SERVER_IP} -m multiport --dports 53,67 -j ACCEPT"
        fi
    fi
    # allow workstations
    if [ -n "$WORKSTATIONS" ]
    then
        if [ -n "$GUEST_IF" ]
        then
            # workstations on main network can connect to guests
            for host in $WORKSTATIONS
            do
                getHostIP "$host" hostip
                FIREWALL="${FIREWALL}
iptables -I FORWARD -i br0 -o ${GUEST_IF} -s $hostip -j ACCEPT"
            done
        fi
        if [ -n "$IOT_IF" ]
        then
            # workstations on main network can connect to IoT
            for host in $WORKSTATIONS
            do
                getHostIP "$host" hostip
                FIREWALL="${FIREWALL}
iptables -I FORWARD -i br0 -o ${IOT_IF} -s $hostip -j ACCEPT"
            done
        fi
    fi
    item=
    subnet=
    dir=
    host=
    peer=
    port=
    for item in ${FIREWALL_RULES}
    do
        if [ -z "$subnet" ]
        then
            subnet=$item
        elif [ -z "$dir" ]
        then
            dir=$item
        elif [ -z "$host" ]
        then
            host=$item
        elif [ -z "$peer" ]
        then
            peer=$item
        elif [ -z "$port" ]
        then
            port=$item
            if expr "$port" : '[0-9][0-9:,]*$' >/dev/null
            then
                getHostIP "$host" hostip
                getSubnetInterface $subnet interface
                if [ -n "$interface" ] && isIPv4 "$hostip"
                then
                    multiport=0
                    if [ $multiport == 0 ] && isSubstring $port ','
                    then
                        multiport=1
                    fi
                    if [ $multiport == 0 ]
                    then
                        if [ "$port" == "0" ]
			then
			    # allow all ports from/to a peer
                            prefix=
                            getSubnetPrefix $subnet prefix
                            count=0
                            getSubnetDistributionCount $peer count
                            index=0
                            while [ $index -lt $count ]
                            do
                                getSubnetDistributionCIDRs $peer $index cidrs
                                for cidr in $cidrs
                                do
                                    if [ $dir == from ]
                                    then
                                        FIREWALL="${FIREWALL}
iptables -I FORWARD -i br0 -o ${interface} -s ${hostip} -d ${prefix}$cidr -j ACCEPT"
                                    else
                                        FIREWALL="${FIREWALL}
iptables -I INPUT -i ${interface} -s ${prefix}$cidr -d ${hostip} -j ACCEPT
iptables -I FORWARD -i ${interface} -s ${prefix}$cidr -d ${hostip} -j ACCEPT"
                                    fi
                                done
                                let index=$index+1
                            done
			else
                            if [ $dir == from ]
                            then
                                FIREWALL="${FIREWALL}
iptables -I FORWARD -i br0 -o ${interface} -p tcp -s ${hostip} --dport $port -j ACCEPT
iptables -I FORWARD -i br0 -o ${interface} -p udp -s ${hostip} --dport $port -j ACCEPT"
                            else
                                FIREWALL="${FIREWALL}
iptables -I INPUT -i ${interface} -p tcp -d ${hostip} --dport $port -j ACCEPT
iptables -I INPUT -i ${interface} -p udp -d ${hostip} --dport $port -j ACCEPT
iptables -I FORWARD -i ${interface} -p tcp -d ${hostip} --dport $port -j ACCEPT
iptables -I FORWARD -i ${interface} -p udp -d ${hostip} --dport $port -j ACCEPT"
                            fi
			fi
                    else
                        if [ $dir == from ]
                        then
                            FIREWALL="${FIREWALL}
iptables -I FORWARD -i br0 -o ${interface} -p tcp -s ${hostip} -m multiport --dports $port -j ACCEPT
iptables -I FORWARD -i br0 -o ${interface} -p udp -s ${hostip} -m multiport --dports $port -j ACCEPT"
                        else
                            FIREWALL="${FIREWALL}
iptables -I INPUT -i ${interface} -p tcp -d ${hostip} -m multiport --dports $port -j ACCEPT
iptables -I INPUT -i ${interface} -p udp -d ${hostip} -m multiport --dports $port -j ACCEPT
iptables -I FORWARD -i ${interface} -p tcp -d ${hostip} -m multiport --dports $port -j ACCEPT
iptables -I FORWARD -i ${interface} -p udp -d ${hostip} -m multiport --dports $port -j ACCEPT"
                        fi
                    fi
                fi
            fi
            subnet=
            dir=
            host=
            peer=
            port=
        fi
    done

    name=
    port=
    host=
    destport=
    forwards=
    num=0

    for item in ${PORT_FORWARDS}
    do
        if [ -z "$name" ]
        then
            name=$item
        elif [ -z "$port" ]
        then
            port=$item
        elif [ -z "$host" ]
        then
            host=$item
        elif [ -z "$destport" ]
        then
            destport=$item
            ip=
            getHostIP $host ip
            if [ -n "$ip" ]
            then
                forwards="${forwards}$name:on:both:$port>$ip:$destport "
                let num=$num+1
            fi
            name=
            port=
            host=
            destport=
        fi
    done

    setNVRam forwardspec_entries $num
    setNVRam forward_spec "${forwards}"

    FIREWALL="${FIREWALL}
iptables -D INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -I INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
"
    setNVRam rc_firewall "$FIREWALL"
    #    if [ "$AS_SWITCH" == 1 ]
    #> arp_spoofing=0
    #> block_ident=0
    #> block_snmp=0
    #> block_wan=0
    #> limit_ftp=0
    #> filter=off
    #> block_multicast=1

    if [ -n "$DMZ_IP" ]
    then
        setNVRam dmz_enable 1
        setNVRam dmz_ipaddr "${DMZ_IP}"
    fi

    # other examples
    ## external SSH
    #iptables -I INPUT -p tcp -m tcp -d $LAN_IP --dport 22 -j logaccept
    #iptables -t nat -I PREROUTING -p tcp -m tcp -d $WAN_IP --dport 2222 -j DNAT --to-destination $LAN_IP:22
    #
    ## block internet access to a IP
    #iptables -I  FORWARD 1 -d 123.123.123.123 -j DROP
    #
    ## block new connections from an IP allowing only port NTP-123 and SMTP/TLS-465
    #iptables -I FORWARD -p tcp -s 192.168.1.50 -m state --state NEW -j DROP
    #iptables -I FORWARD -p udp -s 192.168.1.50 -m state --state NEW -j DROP
    #iptables -I FORWARD -p udp -s 192.168.1.50 --dport 123 -j ACCEPT
    #iptables -I FORWARD -p tcp -s 192.168.1.50 --dport 425 -m state --state NEW -j ACCEPT

    # force all DNS requests to go to a specific DNS server (say Pi-hole), pihole on .60 and router on .1
    #iptables -t nat -I PREROUTING -i br0 -p tcp ! -s 192.168.1.60 --dport 53 -j DNAT --to 192.168.1.60
    #iptables -t nat -I PREROUTING -i br0 -p udp ! -s 192.168.1.60 --dport 53 -j DNAT --to 192.168.1.60
    #iptables -t nat -I POSTROUTING -o br0 -p tcp ! -s 192.168.1.60 --dport 53 -j SNAT --to 192.168.1.1
    #iptables -t nat -I POSTROUTING -o br0 -p udp ! -s 192.168.1.60 --dport 53 -j SNAT --to 192.168.1.1
}

setupNetworking() {
    if [ -z "$WAN" ] || [ "${WAN#dhcp}" != "${WAN}" ]
    then
        setNVRam wan_proto dhcp
    elif [ "${WAN#static}" != "${WAN}" ]
    then
        ip=
        mask=
        dns=
        gateway=
        for item in ${WAN#static}
        do
            if [ -z "$ip" ]
            then
                ip=$item
            elif [ -z "$mask" ]
            then
                mask=$item
            elif [ -z "$gateway" ]
            then
                gateway=$item
            else
                dns=$item
            fi
        done
        setNVRam wan_proto static
        setNVRam wan_ipaddr $ip
        setNVRam wan_netmask $mask
        setNVRam wan_gateway $gateway
        setNVRam wan_dns $dns
    fi
    #    if [ "$AS_SWITCH" == 1 ]
    #    then
    # for switch Admin/Mgmt
    #> zebra_enable=0
    # Setup->Basic
    #> fullswitch=1
    #> lan_ipaddr=192.168.1.4
    #> lan_proto=static
    #> recursive_dns=0
    #> wan_priority=0
    #> wan_proto=disabled
    #> dns_dnsmasq=0
    #Setup->Adv Routing
    #> wk_mode=static
    #    fi
    setupDHCP
    setupStaticLeases
    setupDNS
    setupFirewall
}

defineSubnets
defineSubnetDistribution
defineStaticLeases

getSubnetPrefix Main MAIN_SUBNET
if [ "$SETUP_NETWORKING" == "1" ]
then
    LAN_IP=`nvram get lan_ipaddr`
    WAN_IP=`nvram get wan_ipaddr`

    VALID=0
    case "$LAN_IP" in
        ${MAIN_SUBNET}*) VALID=1 ;;
        *) VALID=0 ;;
    esac

    if [ "$VALID" == 0 ]
    then
        echo "Invalid network configuration detected"
        exit 1
    fi
fi

GUEST_IF=
if isSubstring "$SUBNETS_ALL" Guest
then
    getSubnetInterface Guest GUEST_IF
    getSubnetPrefix Guest GUEST_SUBNET
fi
IOT_IF=
if isSubstring "$SUBNETS_ALL" IoT
then
    getSubnetInterface IoT IOT_IF
    getSubnetPrefix IoT IOT_SUBNET
fi

if [ "$BACKUP" == 1 ]
then
    backupSetup
fi

if [ "$SETUP_BASIC" == 1 ]
then
    setupBasic
fi

if [ "$SETUP_NETWORKING" == 1 ]
then
    setupNetworking
elif [ "$SETUP_STATICLEASE" == 1 ]
then
    setupStaticLeases
elif [ "$SETUP_FIREWALL" == 1 ]
then
    setupFirewall
fi

