let
  # "sensor value stayed above X for a while" -> one ntfy push, rate-limited.
  # Uses the generic `rest_command.ntfy` (see ha/default.nix).
  mkHighAlert =
    { id
    , alias
    , entity
    , above
    , sustained ? "00:10:00" # ignore short spikes (someone walking past, etc.)
    , quietMinutes ? 45 # minimum gap between two pushes from this automation
    , title
    , message
    , priority ? "default"
    , tags ? "house"
    }: {
      inherit id alias;
      mode = "single";
      trigger = [{
        platform = "numeric_state";
        entity_id = entity;
        inherit above;
        for = sustained;
      }];
      # A numeric_state trigger only fires on *crossing* the threshold, but a
      # value hovering around it can cross repeatedly. `last_triggered` advances
      # only when the action actually runs, so this is a real rate limit.
      # `this` is the automation's own state object — no hardcoded entity_id.
      condition = [{
        condition = "template";
        value_template = "{{ as_timestamp(now()) - as_timestamp(state_attr(this.entity_id, 'last_triggered') or 0) > ${toString (quietMinutes * 60)} }}";
      }];
      action = [{
        service = "rest_command.ntfy";
        data = { inherit title message priority tags; };
      }];
    };

  # --- CO2, gabinet ---------------------------------------------------------
  # Entity id is HA's slug of the mqtt sensor's name ("CO2 gabinet", see
  # ha/mqtt_sensors.nix). If these never fire, confirm it in Developer Tools ->
  # States.
  co2Study = "sensor.co2_gabinet";
  # Measured baseline in this room: ~500 ppm with the door open (outdoor air is
  # ~420), ~600 ppm occupied, 2500 ppm peak over a week of closed-door work.
  # Reference points: <800 ppm is "good" by every IAQ guideline (too low to be
  # actionable here), 1000 ppm is the classic ventilate-now limit where
  # stuffiness complaints start, ~1400 ppm is where studies measure a drop in
  # decision-making performance, 2000 ppm brings headaches/drowsiness.
  # So: nudge at 1000, insist at 1500. On a normally ventilated day neither
  # fires; the sessions that produced the 2500 peak get caught early.
  co2WarnPpm = 1000;
  co2HighPpm = 1500;

  # --- Water valves ---------------------------------------------------------
  # The four motorised water valves (../home/valves/water_valve.yaml) sit fully
  # open all year, and a valve that never moves is exactly what limescale
  # seizes, so they get driven through one full close/open cycle a month.
  waterValves = [
    "valve.boneio_1_zawor_kuchnia_ciepla"
    "valve.boneio_1_zawor_kuchnia_zimna"
    "valve.boneio_1_zawor_lazienka_ciepla"
    "valve.boneio_1_zawor_lazienka_zimna"
  ];
  # The valves report no position (the template valve is `optimistic` /
  # `assumed_state`), so the only way to know travel finished is to wait the
  # motor out. 30s is deliberately generous: internal limit switches cut the
  # motor at the end of travel, so holding the relays longer costs nothing but
  # standby current.
  valveTravel = "00:00:30";

  # Appliance power meters (SDM120 over RS-485). Use `l1_power`, NOT
  # `total_power_watt`: the latter reads a flat 0.0 even mid-cycle (checked
  # against a full dishwasher run that `l1_power` showed at 45-70 W), so a
  # guard built on it would never block anything.
  pralkaPower = "sensor.boneio_24_sw_07_737d50_licznik_pradu_pralka_l1_power";
  zmywarkaPower = "sensor.boneio_24_sw_07_737d50_licznik_pradu_zmywarka_l1_power";
  # Only the two appliances that actually draw water. 
  applianceMeters = [ pralkaPower zmywarkaPower ];
  # Standby on these circuits measures ~0.5 W and a running cycle is tens to
  # thousands of watts, so 10 W separates idle from working with a wide margin
  # either side.
  applianceIdleWatts = 10;
in
[
  (mkHighAlert {
    id = "notify_study_co2_elevated";
    alias = "Notify when study CO2 is elevated";
    entity = co2Study;
    above = co2WarnPpm;
    title = "Study air is getting stale";
    message = "CO2 w gabinecie: {{ states('${co2Study}') | round(0) }} ppm (> ${toString co2WarnPpm}). Open a window.";
    tags = "wind_face,house";
  })
  (mkHighAlert {
    id = "notify_study_co2_high";
    alias = "Notify when study CO2 is high";
    entity = co2Study;
    above = co2HighPpm;
    # Already clearly stale by now: react faster and nag more often.
    sustained = "00:05:00";
    quietMinutes = 20;
    title = "Study CO2 is high";
    message = "CO2 w gabinecie: {{ states('${co2Study}') | round(0) }} ppm (> ${toString co2HighPpm}). Wietrz teraz.";
    priority = "high";
    tags = "warning,wind_face";
  })
  {
    id = "notify_front_door_unlocked_at_23";
    alias = "Notify if front door still unlocked at 23:00";
    trigger = [{
      platform = "time";
      at = "23:00:00";
    }];
    # Only remind when the door is actually still unlocked at 23:00. This push
    # is now the *only* night-time handling: the automations that used to lock
    # the door at 23:00 and re-lock it later in the night were deliberately
    # removed, so nothing auto-locks any more and acting on the push is
    # manual.
    condition = [{
      condition = "state";
      entity_id = "lock.drzwi_glowne";
      state = "unlocked";
    }];
    action = [{
      service = "rest_command.ntfy_front_door";
    }];
  }
  {
    id = "m5dial_to_light";
    alias = "M5Dial -> light";
    trigger = [{
      platform = "mqtt";
      topic = "room/light/m5dial/set";
    }];
    action = [{
      choose = [
        {
          conditions = [{
            condition = "template";
            value_template = "{{ trigger.payload_json.state == 'ON' }}";
          }];
          sequence = [{
            service = "light.turn_on";
            target.entity_id = "light.boneio_dr_8ch_03_39835c_light_k";
            data = {
              brightness = "{{ trigger.payload_json.brightness | int }}";
              color_temp_kelvin = "{{ (1000000 / (trigger.payload_json.color_temp | int)) | int }}";
            };
          }];
        }
        {
          conditions = [{
            condition = "template";
            value_template = "{{ trigger.payload_json.state == 'OFF' }}";
          }];
          sequence = [{
            service = "light.turn_off";
            target.entity_id = "light.boneio_dr_8ch_03_39835c_light_k";
          }];
        }
      ];
    }];
  }
  {
    id = "mqtt_to_study_curtains";
    alias = "MQTT -> study curtains";
    trigger = [{
      platform = "mqtt";
      topic = "room/cover/study_curtains/set";
    }];
    action = [{
      choose = [
        {
          conditions = [{
            condition = "template";
            value_template = "{{ trigger.payload_json.state == 'OPEN' }}";
          }];
          sequence = [{
            service = "cover.open_cover";
            target.entity_id = "cover.boneio_24_sw_07_737d50_gabinet_zaslony";
          }];
        }
        {
          conditions = [{
            condition = "template";
            value_template = "{{ trigger.payload_json.state == 'CLOSE' }}";
          }];
          sequence = [{
            service = "cover.close_cover";
            target.entity_id = "cover.boneio_24_sw_07_737d50_gabinet_zaslony";
          }];
        }
        {
          conditions = [{
            condition = "template";
            value_template = "{{ trigger.payload_json.state == 'STOP' }}";
          }];
          sequence = [{
            service = "cover.stop_cover";
            target.entity_id = "cover.boneio_24_sw_07_737d50_gabinet_zaslony";
          }];
        }
        {
          conditions = [{
            condition = "template";
            value_template = "{{ trigger.payload_json.position is defined }}";
          }];
          sequence = [{
            service = "cover.set_cover_position";
            target.entity_id = "cover.boneio_24_sw_07_737d50_gabinet_zaslony";
            data.position = "{{ trigger.payload_json.position | int }}";
          }];
        }
      ];
    }];
  }
  {
    id = "close_study_curtains_at_2";
    alias = "Close study curtains at 02:00";
    trigger = [{
      platform = "time";
      at = "02:00:00";
    }];
    action = [{
      service = "cover.close_cover";
      target.entity_id = "cover.boneio_24_sw_07_737d50_gabinet_zaslony";
    }];
  }
  {
    id = "close_bedroom_curtains_at_23";
    alias = "Close bedroom curtains at 23:00";
    trigger = [{
      platform = "time";
      at = "23:00:00";
    }];
    action = [{
      service = "button.press";
      target.entity_id = "button.boneio_24_sw_07_737d50_sypialnia_zaslony_zamknij";
    }];
  }
  {
    id = "open_bedroom_curtains_at_7_weekdays";
    alias = "Open bedroom curtains at 07:00 on weekdays";
    trigger = [{
      platform = "time";
      at = "07:00:00";
    }];
    # Mon–Fri only; weekends are intentionally skipped so the bedroom stays
    # dark for sleeping in.
    condition = [{
      condition = "time";
      weekday = [ "mon" "tue" "wed" "thu" "fri" ];
    }];
    action = [{
      service = "button.press";
      target.entity_id = "button.boneio_24_sw_07_737d50_sypialnia_zaslony_otworz";
    }];
  }
  {
    id = "study_curtains_to_mqtt";
    alias = "study curtains -> MQTT";
    trigger = [{
      platform = "state";
      entity_id = "cover.boneio_24_sw_07_737d50_gabinet_zaslony";
    }];
    action = [{
      service = "mqtt.publish";
      data = {
        topic = "room/cover/study_curtains/state";
        retain = true;
        payload = ''{{ {"state": trigger.to_state.state | upper, "position": trigger.to_state.attributes.current_position | default(0, true) | int} | tojson }}'';
      };
    }];
  }
  {
    id = "pralnia_door_light";
    alias = "Pralnia door -> light";
    trigger = [
      {
        platform = "state";
        entity_id = "binary_sensor.pralnia_drzwi";
        to = "on";
      }
      {
        platform = "state";
        entity_id = "binary_sensor.pralnia_drzwi";
        to = "off";
      }
    ];
    action = [{
      choose = [
        {
          conditions = [{
            condition = "state";
            entity_id = "binary_sensor.pralnia_drzwi";
            state = "on";
          }];
          sequence = [{
            service = "light.turn_on";
            target.entity_id = "light.boneio_dr_8ch_03_4023d4_light_n";
          }];
        }
        {
          conditions = [{
            condition = "state";
            entity_id = "binary_sensor.pralnia_drzwi";
            state = "off";
          }];
          sequence = [{
            service = "light.turn_off";
            target.entity_id = "light.boneio_dr_8ch_03_4023d4_light_n";
          }];
        }
      ];
    }];
  }
  {
    id = "front_door_open_hall_light_afternoon";
    alias = "Front door open -> hall light (afternoon/evening/night)";
    # in_13 on boneio-24-sw-07-737d50 is the front-door reed switch
    # The HA entity id slugs the *friendly* device name ("boneio-1"), not the
    # esphome node name, hence binary_sensor.boneio_1_*. It reports
    # device_class door (on = Open), so the purpose-specific `door.opened`
    # trigger would fit — but that family is still Labs-gated on this
    # instance's HA core (2026.5) and only becomes default config in 2026.7.
    # Keep the plain state trigger until then.
    trigger = [{
      platform = "state";
      entity_id = "binary_sensor.boneio_1_czujnik_otwarcia_drzwi";
      to = "on";
    }];
    # Which light depends on the hour: the overhead "górne" until midnight,
    # the floor-level "podłogowe" after it, so coming home at 2am doesn't
    # mean full ceiling light. The two windows are disjoint, so the order of
    # the branches carries no meaning.
    #
    # Each branch also requires its own light to be off, so walking in and out
    # does not re-issue turn_on against a light someone already dimmed by
    # hand. When that guard fails the branch is skipped and the other branch's
    # time condition rejects it too, so nothing happens — which is the intent.
    action = [{
      choose = [
        {
          # 13:00 -> 00:00. A one-sided `after` anchors at midnight, which is
          # exactly the upper bound wanted here; the small hours are the next
          # branch's job.
          conditions = [
            {
              condition = "time";
              after = "13:00:00";
            }
            {
              condition = "state";
              entity_id = "light.boneio_dr_8ch_03_32ce68_light_a1_d1";
              state = "off";
            }
          ];
          sequence = [{
            service = "light.turn_on";
            target.entity_id = "light.boneio_dr_8ch_03_32ce68_light_a1_d1";
          }];
        }
        {
          # 00:00 -> 06:00. Both bounds are spelled out: a lone `before` would
          # work (it anchors at midnight too), but stating both keeps the
          # window readable next to the branch above.
          conditions = [
            {
              condition = "time";
              after = "00:00:00";
              before = "06:00:00";
            }
            {
              condition = "state";
              entity_id = "light.boneio_dr_8ch_03_39835c_light_c";
              state = "off";
            }
          ];
          sequence = [{
            service = "light.turn_on";
            target.entity_id = "light.boneio_dr_8ch_03_39835c_light_c";
          }];
        }
      ];
    }];
  }
  {
    id = "mata_grzewcza_schedule";
    alias = "Mata grzewcza - harmonogram";
    # Drive the ESPHome thermostat (climate) rather than the raw
    # switch.mata_grzewcza output, so the on/off schedule cooperates with the
    # thermostat's control loop (temp_mata sensor) instead of fighting it. The
    # thermostat only has "off"/"heat" modes; "heat" lets it decide when to
    # actually energize the mat.
    # Follow the `schedule.mata_grzewcza` helper: heat while a scheduled block
    # is active, off otherwise. Per-weekday/weekend windows live in the helper
    # (see ha/default.nix), so this stays two triggers regardless of how many
    # windows are configured.
    trigger = [
      {
        platform = "state";
        entity_id = "schedule.mata_grzewcza";
        to = "on";
        id = "on";
      }
      {
        platform = "state";
        entity_id = "schedule.mata_grzewcza";
        to = "off";
        id = "off";
      }
    ];
    action = [{
      choose = [
        {
          conditions = [
            {
              condition = "trigger";
              id = "on";
            }
            # Heating season only: September–May. Summer (Jun–Aug) blocks still
            # fire the "on" trigger, but this gates the heat action, so the mat
            # stays off. The "off" branch has no such gate, so end-of-block
            # always switches it off.
            {
              condition = "template";
              value_template = "{{ now().month >= 9 or now().month <= 5 }}";
            }
          ];
          sequence = [{
            service = "climate.set_hvac_mode";
            target.entity_id = "climate.boneio_24_sw_07_737d50_mata_grzewcza_termostat";
            data.hvac_mode = "heat";
          }];
        }
        {
          conditions = [{
            condition = "trigger";
            id = "off";
          }];
          sequence = [{
            service = "climate.set_hvac_mode";
            target.entity_id = "climate.boneio_24_sw_07_737d50_mata_grzewcza_termostat";
            data.hvac_mode = "off";
          }];
        }
      ];
    }];
  }
  {
    id = "water_valve_monthly_exercise";
    alias = "Water valves - monthly exercise";
    # First Sunday of the month at 04:00: drive every water valve through one
    # close/open cycle so limescale never gets to set around a valve that has
    # not moved in months. 04:00 on a Sunday is the quietest slot in the week.
    mode = "single";
    trigger = [{
      platform = "time";
      at = "04:00:00";
    }];
    condition = [
      {
        condition = "time";
        weekday = [ "sun" ];
      }
      # The first Sunday of a month is the only one landing on day 1-7. HA has
      # no native "nth weekday" condition, so this is the one template needed.
      {
        condition = "template";
        value_template = "{{ now().day <= 7 }}";
      }
    ];
    # The idle check sits in `choose` rather than in `condition` above so that a
    # blocked run still reaches `default` and says so, instead of skipping in
    # silence and leaving the valves un-exercised for another month unnoticed.
    action = [{
      choose = [{
        # Every meter must read idle. A numeric_state condition is false for a
        # non-numeric state, so `unknown`/`unavailable` blocks the cycle too.
        # That is deliberate: an unreadable meter is not evidence the appliance
        # is idle, and shutting the water on a running washer is the single
        # outcome worth avoiding here.
        conditions = builtins.map
          (entity: {
            condition = "numeric_state";
            entity_id = entity;
            below = applianceIdleWatts;
          })
          applianceMeters;
        sequence =
          # One valve at a time, so no supply point is shut for longer than its
          # own cycle and the relay board never drives four motors at once.
          builtins.concatMap
            (valve: [
              {
                service = "valve.close_valve";
                target.entity_id = valve;
              }
              { delay = valveTravel; }
              {
                service = "valve.open_valve";
                target.entity_id = valve;
              }
              { delay = valveTravel; }
            ])
            waterValves
          ++ [
            # Belt and braces: end with every valve commanded open regardless
            # of what the per-valve steps did. Idempotent, and it repairs a
            # valve left closed by an earlier run that died mid-sequence.
            {
              service = "valve.open_valve";
              target.entity_id = waterValves;
            }
          ];
      }];
      # Keep title/tags ASCII - ntfy sends them as HTTP headers (see the
      # rest_command.ntfy comment in ha/default.nix). The body may be UTF-8.
      default = [{
        service = "rest_command.ntfy";
        data = {
          title = "Water valve check skipped";
          message = "Miesięczny przegląd zaworów pominięty: licznik pokazuje pracę albo nie odpowiada (próg ${toString applianceIdleWatts} W). pralka: {{ states('${pralkaPower}') }}, zmywarka: {{ states('${zmywarkaPower}') }}. Zawory nietknięte, następna próba w pierwszą niedzielę kolejnego miesiąca.";
          tags = "droplet,warning";
        };
      }];
    }];
  }
  {
    id = "light_to_m5dial";
    alias = "light -> M5Dial";
    trigger = [{
      platform = "state";
      entity_id = "light.boneio_dr_8ch_03_39835c_light_k";
    }];
    action = [{
      service = "mqtt.publish";
      data = {
        topic = "room/light/m5dial/state";
        retain = true;
        payload = ''{{ {"state": trigger.to_state.state | upper, "brightness": trigger.to_state.attributes.brightness | default(128, true) | int, "color_temp": trigger.to_state.attributes.color_temp | default(370, true) | int} | tojson }}'';
      };
    }];
  }
  {
    id = "all_lights_off_mirror";
    alias = "All lights off (mirror dimmer-1 wall button)";
    # Reliability backup for the ESPHome UDP all-off mechanism. The dimmer-1
    # wall button (in_01, "1.1 (433)") turns off dimmer-1's own lights and
    # broadcasts "udp_all_off" over UDP; the other dimmers listen and switch
    # off. That broadcast is best-effort and occasionally drops a dimmer. When
    # HA is up we ALSO press the per-dimmer `ha_all_off` button on every dimmer
    # directly over the ESPHome native API (acked, reliable), so a dropped UDP
    # packet still gets covered. When HA is down the UDP path keeps working on
    # its own, so nothing regresses.
    #
    # NOTE: the trigger entity_id is HA's slug of the ESPHome name "1.1 (433)".
    # If this automation never fires, confirm the exact id in HA Developer
    # Tools -> States (search for the dimmer-1 inputs) and adjust it here.
    trigger = [{
      platform = "state";
      entity_id = "binary_sensor.boneio_dr_8ch_03_32ce68_1_1_433";
      to = "on";
    }];
    action = [{
      service = "button.press";
      target.entity_id = [
        "button.dimmer_1_hall_wylacz_wszystkie_swiatla_ha"
        "button.dimmer_2_bedroom_wylacz_wszystkie_swiatla_ha"
        "button.dimmer_3_bedroom_wylacz_wszystkie_swiatla_ha"
        "button.dimmer_4_study_wylacz_wszystkie_swiatla_ha"
        "button.dimmer_5_bathroom_wylacz_wszystkie_swiatla_ha"
        "button.dimmer_6_livingroom_wylacz_wszystkie_swiatla_ha"
        "button.dimmer_7_kitchen_wylacz_wszystkie_swiatla_ha"
      ];
    }];
  }
]
