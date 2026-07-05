{ pkgs, config, lib, ... }:
let
  # Roaming/steering machinery advertised on both koteczkowo5 BSSes (2.4 GHz on
  # wlan0 + 5 GHz on wlan1) so dual-band clients can move between the radios
  # cleanly instead of thrashing: 802.11k neighbor/beacon reports, 802.11v BSS
  # Transition Management, and MBO. hostapd auto-populates the neighbor DB with
  # its co-located BSSes when rrm_neighbor_report is on. Requires WMM + PMF, both
  # already enabled on koteczkowo5.
  roamingSettings = {
    bss_transition = 1;
    rrm_neighbor_report = 1;
    rrm_beacon_report = 1;
    mbo = 1;
  };

  # 802.11r Fast BSS Transition across the two koteczkowo5 BSSes (2.4 GHz on
  # wlan0 + 5 GHz on wlan1). Without it, every band change is a full WPA3-SAE
  # re-auth and the PMF (ieee80211w=2) SA-Query dance tears roaming clients off
  # with "local deauth request" — the loop both the MacBook Pro and the Intel
  # laptop hit on 5 GHz. FT turns a band change into a fast handoff instead.
  #
  # Both BSSes run in the same hostapd process, so PMK-R1 distribution stays
  # on-box via internal RRB; the wildcard r0kh/r1kh share-key never leaves the
  # device. ft_over_ds=0 uses over-the-air FT (most compatible).
  #
  # The r0kh/r1kh lines (which embed the shared key) live in an agenix secret
  # and are pulled in via hostapd's rxkh_file, so the key never lands in the
  # nix store or the generated config — same approach as saePasswordsFile.
  mkFt = nasId: {
    # NB: there is no `ieee80211r` option in hostapd.conf — that's an OpenWrt/UCI
    # name. FT is enabled purely by putting FT-SAE in wpa_key_mgmt plus the
    # mobility_domain/ft_over_ds params below and the r0kh/r1kh from rxkh_file.
    # Setting `ieee80211r` makes hostapd abort with "unknown configuration item".
    wpa_key_mgmt = lib.mkForce "SAE FT-SAE";
    mobility_domain = "e50a";
    ft_over_ds = 0;
    pmk_r1_push = 1;
    nas_identifier = nasId;
    rxkh_file = config.age.secrets.surferFtKey.path;
  };
in
{
  # wireless access point
  services.hostapd = {
    enable = true;
    radios = {
      wlan0 = {
        band = "2g";
        countryCode = "PL";
        channel = 0; # ACS

        # use 'iw phy#1 info' to determine your VHT capabilities
        wifi4 = {
          enable = true;
          capabilities = [ "HT40+" "LDPC" "SHORT-GI-20" "SHORT-GI-40" "TX-STBC" "RX-STBC1" "MAX-AMSDU-7935" ];
        };
        wifi6 = {
          enable = true;
          operatingChannelWidth = "20or40";
        };
        networks = {
          wlan0 = {
            ssid = "koteczkowo5";
            authentication = {
              mode = "wpa3-sae";
              saePasswordsFile = config.age.secrets.wifiPassword.path;
            };
            # fake bsside to satisfy module assertion
            # overided by ddynamicConfigScripts
            bssid = "00:00:00:00:00:00";
            settings = {
              bridge = "br-lan";
              dtim_period = 3;
              wmm_enabled = true;
              ieee80211w = "2";
              ap_max_inactivity = 600;
              disassoc_low_ack = 0;
            } // roamingSettings // (mkFt "surfer-koteczkowo5-2g");
            dynamicConfigScripts = {
              "20-bssidFile" = pkgs.writeShellScript "bssid-file" ''
                HOSTAPD_CONFIG_FILE=$1
                grep -v '\s*#' ${lib.escapeShellArg config.age.secrets.wlan00bssid.path} \
                  | sed 's/^/bssid=/' >> "$HOSTAPD_CONFIG_FILE"
              '';
            };
          };
          # working with esp8266 but doesn't work with rpi5
          wlan0-1 = {
            ssid = "koteczkowo3";
            authentication = {
              mode = "none"; # this is overriden by settings
            };
            # fake bsside to satisfy module assertion
            # overided by ddynamicConfigScripts
            bssid = "00:00:00:00:00:00";
            settings = {
              bridge = "br-lan";
              wmm_enabled = false;
              ieee80211w = "0";
              wpa = lib.mkForce 2;
              wpa_key_mgmt = "WPA-PSK";
              wpa_pairwise = "CCMP";
              wpa_psk_file = config.age.secrets.legacyWifiPassword.path;
              # sae_require_mfp = false;
            };

            dynamicConfigScripts = {
              "20-bssidFile" = pkgs.writeShellScript "bssid-file" ''
                HOSTAPD_CONFIG_FILE=$1
                grep -v '\s*#' ${lib.escapeShellArg config.age.secrets.wlan01bssid.path} \
                  | sed 's/^/bssid=/' >> "$HOSTAPD_CONFIG_FILE"
              '';
            };
          };
          # working with rpi5
          # wlan0-1 = {
          #   ssid = "koteczkowo3";
          #   authentication = {
          #     mode = "wpa3-sae-transition"; # this is overriden by settings
          #     wpaPskFile = config.age.secrets.legacyWifiPassword.path;
          #     saePasswordsFile = config.age.secrets.legacyWifiPassword2.path;
          #   };
          #   # managementFrameProtection = "optional";
          #   bssid = "e6:02:43:07:00:00";
          #   settings = {
          #     bridge = "br-lan";
          #     ieee80211w = "2";
          #     # sae_require_mfp = false;
          #   };
          # };
        };
      };
      wlan1 = {
        band = "5g";
        channel = 36; # UNII-1 (5180 MHz), non-DFS
        countryCode = "PL";

        # use 'iw phy#1 info' to determine your VHT capabilities
        wifi4 = {
          enable = true;
          capabilities = [ "HT40+" "LDPC" "SHORT-GI-20" "SHORT-GI-40" "TX-STBC" "RX-STBC1" "MAX-AMSDU-7935" ];
        };
        wifi5 = {
          enable = true;
          operatingChannelWidth = "80";
          capabilities = [ "RXLDPC" "SHORT-GI-80" "SHORT-GI-160" "TX-STBC-2BY1" "SU-BEAMFORMER" "SU-BEAMFORMEE" "MU-BEAMFORMER" "MU-BEAMFORMEE" "RX-ANTENNA-PATTERN" "TX-ANTENNA-PATTERN" "RX-STBC-1" "SOUNDING-DIMENSION-4" "BF-ANTENNA-4" "VHT160" "MAX-MPDU-11454" "MAX-A-MPDU-LEN-EXP7" ];
        };
        wifi6 = {
          enable = true;
          singleUserBeamformer = true;
          singleUserBeamformee = true;
          multiUserBeamformer = true;
          operatingChannelWidth = "80";
        };
        settings = {
          dtim_period = 3;
          ieee80211w = "2";
          ap_max_inactivity = 600;
          disassoc_low_ack = 0;
          # 80 MHz on ch36 (center ch42 / 5210 MHz). 160 MHz is not possible here:
          # the PL/ETSI regdomain caps 5150-5350 (ch36-64) at 80 MHz per subband,
          # and the only 160 MHz block (ch100-144) is DFS. Previously this asked for
          # 160 MHz + seg0_idx=50 but mac80211 clamped it to 80 MHz anyway.
          #
          # The hostapd NixOS module emits vht/he_oper_chwidth from
          # operatingChannelWidth but does NOT derive the segment-0 center-frequency
          # index, so it must be set explicitly. Without it hostapd computes a bogus
          # channel index ("DFS chan_idx seems wrong; ch-no: -6") and aborts wlan1
          # interface init. For the 36/40/44/48 block the 80 MHz center is ch42.
          vht_oper_centr_freq_seg0_idx = 42;
          he_oper_centr_freq_seg0_idx = 42;

          # The "tx_queue_data2_burst" parameter in Linux refers to the burst size for 
          # transmitting data packets from the second data queue of a network interface. 
          # It determines the number of packets that can be sent in a burst. 
          # Adjusting this parameter can impact network throughput and latency.
          tx_queue_data2_burst = 2;


          # The "he_bss_color" parameter in Wi-Fi 6 (802.11ax) refers to the BSS Color field in the HE (High Efficiency) MAC header.
          # BSS Color is a mechanism introduced in Wi-Fi 6 to mitigate interference and improve network efficiency in dense deployment scenarios. 
          # It allows multiple overlapping Basic Service Sets (BSS) to differentiate and coexist in the same area without causing excessive interference.
          he_bss_color = 63; # was set to 128 by openwrt but range of possible values in 2.10 is 1-63

          # Magic values that were set by openwrt but I didn't bother inspecting every single one
          he_spr_sr_control = 3;
          he_default_pe_duration = 4;
          he_rts_threshold = 1023;

          he_mu_edca_qos_info_param_count = 0;
          he_mu_edca_qos_info_q_ack = 0;
          he_mu_edca_qos_info_queue_request = 0;
          he_mu_edca_qos_info_txop_request = 0;

          # he_mu_edca_ac_be_aci=0; missing in 2.10
          he_mu_edca_ac_be_aifsn = 8;
          he_mu_edca_ac_be_ecwmin = 9;
          he_mu_edca_ac_be_ecwmax = 10;
          he_mu_edca_ac_be_timer = 255;

          he_mu_edca_ac_bk_aifsn = 15;
          he_mu_edca_ac_bk_aci = 1;
          he_mu_edca_ac_bk_ecwmin = 9;
          he_mu_edca_ac_bk_ecwmax = 10;
          he_mu_edca_ac_bk_timer = 255;

          he_mu_edca_ac_vi_ecwmin = 5;
          he_mu_edca_ac_vi_ecwmax = 7;
          he_mu_edca_ac_vi_aifsn = 5;
          he_mu_edca_ac_vi_aci = 2;
          he_mu_edca_ac_vi_timer = 255;

          he_mu_edca_ac_vo_aifsn = 5;
          he_mu_edca_ac_vo_aci = 3;
          he_mu_edca_ac_vo_ecwmin = 5;
          he_mu_edca_ac_vo_ecwmax = 7;
          he_mu_edca_ac_vo_timer = 255;
        };
        networks = {
          wlan1 = {
            ssid = "koteczkowo5";
            authentication = {

              mode = "wpa3-sae";
              saePasswordsFile = config.age.secrets.wifiPassword.path; # Use saePasswordsFile if possible.
            };
            # fake bsside to satisfy module assertion
            # overided by ddynamicConfigScripts
            bssid = "00:00:00:00:00:00";
            settings = {
              bridge = "br-lan";
            } // roamingSettings // (mkFt "surfer-koteczkowo5-5g");
            dynamicConfigScripts = {
              "20-bssidFile" = pkgs.writeShellScript "bssid-file" ''
                HOSTAPD_CONFIG_FILE=$1
                grep -v '\s*#' ${lib.escapeShellArg config.age.secrets.wlan10bssid.path} \
                  | sed 's/^/bssid=/' >> "$HOSTAPD_CONFIG_FILE"
              '';
            };
          };
        };
      };
    };
  };
}
