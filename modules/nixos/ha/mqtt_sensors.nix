let
  lazienkaMAC = "1B6B0";
  sypialniaMAC = "1C60E";
  pralniaMAC = "1C5F3";
  salonMAC = "1C625";
  gabinetMAC = "1C6ED";
in
[
  {
    device_class = "temperature";
    name = "Temperatura sypialnia";
    state_topic = "ampio/from/${sypialniaMAC}/state/t/1";
    state_class = "measurement";
    unique_id = "ampio_bedroom_temp";
    unit_of_measurement = "°C";
  }
  {
    device_class = "temperature";
    name = "Temperature łazienka";
    state_topic = "ampio/from/${lazienkaMAC}/state/t/1";
    state_class = "measurement";
    unique_id = "ampio_bathroom_temp";
    unit_of_measurement = "°C";
  }
  {
    device_class = "humidity";
    name = "Wilgotność łazienka";
    object_id = "ampio_bathroom_hum";
    state_topic = "ampio/from/${lazienkaMAC}/b/44";
    value_template = "{{ value_json.d[2] + value_json.d[3] * 256 }}";
    unit_of_measurement = "%";
    state_class = "measurement";
  }
  {
    device_class = "temperature";
    name = "Temperatura pralnia";
    state_topic = "ampio/from/${pralniaMAC}/state/t/1";
    state_class = "measurement";
    unique_id = "ampio_laundry_temp";
    unit_of_measurement = "°C";
  }
  {
    device_class = "temperature";
    name = "Temperatura gabinet";
    state_topic = "ampio/from/${gabinetMAC}/state/t/1";
    state_class = "measurement";
    unique_id = "ampio_study_temp";
    unit_of_measurement = "°C";
  }
  {
    device_class = "temperature";
    name = "Temperatura salon";
    state_topic = "ampio/from/${salonMAC}/state/t/1";
    state_class = "measurement";
    unique_id = "ampio_livingroom_temp";
    unit_of_measurement = "°C";
  }

]
