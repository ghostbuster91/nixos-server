let
  lazienkaMAC = "1B6B0";
  sypialniaMAC = "1C60E";
  pralniaMAC = "1C5F3";
  salonMAC = "1C625";
  gabinetMAC = "1C6ED";

  # 16-bit little-endian word at byte offset `idx` of an Ampio broadcast frame
  rawWord = idx: "value_json.d[${toString idx}] + value_json.d[${toString (idx + 1)}] * 256";
  # the big multisensor biases its words by 10000 and scales them by 10
  scaledWord = idx: "((${rawWord idx}) - 10000) / 10";

  optUnit = unit: if unit == null then { } else { unit_of_measurement = unit; };

  mkTemp = { plName, engName, macAddress, probe ? 1, idSuffix ? "temp", label ? "Temperatura" }: {
    device_class = "temperature";
    name = "${label} ${plName}";
    state_topic = "ampio/from/${macAddress}/state/t/${toString probe}";
    state_class = "measurement";
    unique_id = "ampio_${engName}_${idSuffix}";
    unit_of_measurement = "°C";
  };

  # sensor read out of a raw broadcast frame (`ampio/from/<mac>/b/<frame>`)
  mkFrameSensor =
    { plName
    , engName
    , macAddress
    , device_class
    , label
    , idSuffix
    , frame
    , value
    , unit ? null
    }: {
      inherit device_class;
      name = "${label} ${plName}";
      unique_id = "ampio_${engName}_${idSuffix}";
      state_topic = "ampio/from/${macAddress}/b/${toString frame}";
      value_template = "{{ ${value} }}";
      state_class = "measurement";
    } // optUnit unit;

  mkHum = args: mkFrameSensor (args // {
    device_class = "humidity";
    label = "Wilgotność";
    idSuffix = "hum";
    frame = 44;
    value = rawWord 2;
    unit = "%";
  });

  # small multisensor: on-board temperature + humidity only
  mkMSensLight = { plName, engName, macAddress }: [
    (mkTemp { inherit plName engName macAddress; })
    (mkHum { inherit plName engName macAddress; })
  ];

  # full multisensor (temperature + external probe, /b/21 = [hum, press, noise],
  # /b/22 = [lux, IAQ, press], /b/23 = [CO2, IAQ, press])
  mkMSensFull = { plName, engName, macAddress }:
    let
      ids = { inherit plName engName macAddress; };
      frameSensor = args: mkFrameSensor (ids // args);
    in
    [
      (mkTemp ids)
      (frameSensor {
        device_class = "humidity";
        label = "Wilgotność";
        idSuffix = "hum";
        frame = 21;
        value = scaledWord 2;
        unit = "%";
      })
      (frameSensor {
        device_class = "atmospheric_pressure";
        label = "Ciśnienie";
        idSuffix = "press";
        frame = 21;
        value = scaledWord 4;
        unit = "hPa";
      })
      (frameSensor {
        device_class = "sound_pressure";
        label = "Hałas";
        idSuffix = "noise";
        frame = 21;
        value = scaledWord 6;
        unit = "dB";
      })
      (frameSensor {
        device_class = "illuminance";
        label = "Natężenie światła";
        idSuffix = "lux";
        frame = 22;
        value = scaledWord 2;
        unit = "lx";
      })
      (frameSensor {
        device_class = "aqi";
        label = "IAQ";
        idSuffix = "iaq";
        frame = 22;
        value = scaledWord 4;
      })
      (frameSensor {
        device_class = "carbon_dioxide";
        label = "CO2";
        idSuffix = "co2";
        frame = 23;
        value = scaledWord 2;
        unit = "ppm";
      })
    ];
in
builtins.concatLists [
  (mkMSensLight { plName = "sypialnia"; engName = "bedroom"; macAddress = sypialniaMAC; })
  (mkMSensLight { plName = "łazienka"; engName = "bathroom"; macAddress = lazienkaMAC; })
  (mkMSensLight { plName = "pralnia"; engName = "laundry"; macAddress = pralniaMAC; })
  (mkMSensFull { plName = "gabinet"; engName = "study"; macAddress = gabinetMAC; })
  (mkMSensLight { plName = "salon"; engName = "livingroom"; macAddress = salonMAC; })
]
