let
  lazienkaMAC = "1B6B0";
  sypialniaMAC = "1C60E";
  pralniaMAC = "1C5F3";
  salonMAC = "1C625";
  gabinetMAC = "1C6ED";
  mkTemp = { plName, engName, macAddress }: {
    device_class = "temperature";
    name = "Temperatura ${plName}";
    state_topic = "ampio/from/${macAddress}/state/t/1";
    state_class = "measurement";
    unique_id = "ampio_${engName}_temp";
    unit_of_measurement = "°C";
  };
  mkHum = { plName, engName, macAddress }: {
    device_class = "humidity";
    name = "Wilgotność ${plName}";
    unique_id = "ampio_${engName}_hum";
    state_topic = "ampio/from/${macAddress}/b/44";
    value_template = "{{ value_json.d[2] + value_json.d[3] * 256 }}";
    unit_of_measurement = "%";
    state_class = "measurement";
  };
  mkMSensLight = { plName, engName, macAddress }: [
    (mkTemp { inherit plName engName macAddress; })
    (mkHum { inherit plName engName macAddress; })
  ];
in
builtins.concatLists [
  (mkMSensLight { plName = "sypialnia"; engName = "bedroom"; macAddress = sypialniaMAC; })
  (mkMSensLight { plName = "łazienka"; engName = "bathroom"; macAddress = lazienkaMAC; })
  (mkMSensLight { plName = "pralnia"; engName = "laundry"; macAddress = pralniaMAC; })
  [ (mkTemp { plName = "gabinet"; engName = "study"; macAddress = gabinetMAC; }) ]
  (mkMSensLight { plName = "salon"; engName = "livingroom"; macAddress = salonMAC; })
]
