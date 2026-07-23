[
  {
    id = "lock_front_door_at_23";
    alias = "Lock front door at 23:00";
    trigger = [{
      platform = "time";
      at = "23:00:00";
    }];
    action = [{
      service = "lock.lock";
      target.entity_id = "lock.drzwi_glowne";
    }];
  }
  {
    id = "relock_front_door_at_night";
    alias = "Re-lock front door if left unlocked at night";
    trigger = [{
      platform = "state";
      entity_id = "lock.drzwi_glowne";
      to = "unlocked";
      for = "00:10:00";
    }];
    condition = [{
      condition = "time";
      after = "23:00:00";
      before = "06:00:00";
    }];
    action = [{
      service = "lock.lock";
      target.entity_id = "lock.drzwi_glowne";
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
              color_temp = "{{ trigger.payload_json.color_temp | int }}";
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
]
