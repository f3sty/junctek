# Junctek Battery Monitor BLE protocol info

## Tl;DR:
 - Write `0x100` to handle `0x22` (UUID `00002902-0000-1000-8000-00805f9b34fb`) to start receiving records as values change
 - Write `0xbb9aa90cee` to handle `0x25` (UUID `0000fff2-0000-1000-8000-00805f9b34fb`) to trigger a once-off transfer of all parameter values


## Data format
- Records are sent with a start byte of `0xbb` and an end byte of `0xee`.
- Records can contain one or more parameter values.
- Format is `value byte 1 [... value byte N]` **followed** by the parameter type.
- Values are packed BCD, parameter types are in the range `0xb0` to `0xf0`.

| ID | Paramater Name                  | Equation |
|----|---------------------------------|----------|
| b0 |  Battery capacity               | x / 10   |
| b1 |  Over-temp protection (C)       | x - 100  |
| b2 |                                 |          |
| b3 |                                 |          |
| b4 |                                 |          |
| b5 |                                 |          |
| b6 |                                 |          |
| b7 |  Relay mode                     | 0 = N/O, 1=N/C |
| b8 |                                 |          |
| b9 |                                 |          |
| c0 |  Volts                          | x / 100  |
| c1 |  Amps                           | x / 100  |
| c2 |  Protection delay sec           | x = seconds |
| c3 |  Protection recovery sec        | x = seconds |
| c4 |                                 |          |
| c5 |  Over-voltage protection        | x / 100  |
| c6 |  Under-voltage protection       | x / 100  |
| c7 |  Over-current protection        | x / 100  |
| c8 |  Over-current charge protection | x / 100  |
| c9 |  Over-power protection          | x / 100  |
| d0 |  Relay state                    | 0=off, 1=on |
| d1 |  Charge state                   | 0=Discharging, 1=Charging |
| d2 |  Ah remaining                   | x / 1000 |
| d3 |  KWh discharged                 | x / 100000 |
| d4 |  KWh charged                    | x / 100000 |
| d5 |  Total run time                 | x = seconds |
| d6 |  Time remaining                 | x = minutes |
| d7 |  Impedance                      | x / 100 |
| d8 |  Watts                          | x / 100  |
| d9 |  Temperature (C)                | x - 100 |
| e0 |                                 |         |
| e1 |                                 |         |
| e2 |                                 |         |
| e3 |  Under-temp protection          | x - 100 |
| f0 |                                 |         |


State of charge is not a stored parameter, but is calculated with `(d2 / 100) / b0`


## Example
Record recieved:


`bb 08 23 14 44 d5 09 99 99 d2 32 05 66 d3 24 ee`

`bb` = start of record  
`08231444` = 1st param value  
`d5` = 1st param type (Total Run Time of 8231444 seconds, or ~95 days)

`099999` = 2nd param value  
`d2` = 2nd param type (Ah remaining = 99999 / 1000, or 99.99 Ah)

`320566` = 3rd param value  
`d3` = 3rd param type (KWh discharged = 320566 / 100000, or 3.20566)  
`24` = checksum byte  
`ee` = end of record
  



## Operation

 - **Write `0x100` to handle `0x22` (UUID `00002902-0000-1000-8000-00805f9b34fb`) to start receiving records as values change**
This will cause the device to start sending records to the notification handle `0x2d` whenever a parameter value changes.  
If there is no current flowing in or out of the battery, the only parameter that will be changing frequently is `d5` Total Run time, which will increment every second - and if the output relay is set to OFF, you may not see any traffic at all.  
Many of the parameter values will **never** change without manual intervention (e.g. most of the `b*` and the `c*` configuration and protection settings) so these will not be visible without triggering a one-off dump of all parameter values.

 - **Write `0xbb9aa90cee` to handle `0x25` (UUID `0000fff2-0000-1000-8000-00805f9b34fb`) to trigger a once-off transfer of all parameter values**  
 This will cause the device to immediately start sending all the (unordered) parameter values once to the notification handle `0x2d` if it is already sending notifications.


## Perl Script
junctek.pl is a small Perl script that wraps `gatttool` to fetch all the parameter values from a Junctek battery monitor device once, and optionally publish them to an MQTT server.  
(Note: `gatttool` has been deprecated for a while now and one day will disappear from distros)

Parameters can either be set in the configuration section at the start of the script, or supplied on the commandline.
Commandline options override the script settings.

```
Usage: junctek.pl [OPTION?]

Options:
        -d, --device=MAC                Specify remote Bluetooth address
        -q, --quiet                     Don't print output
        -m, --mqtt                      Enable (1) or disable (0) publishing to MQTT
        -s, --server                    Hostname of MQTT server
        -u  --username                  MQTT username
        -p  --password                  MQTT password
        -n, --name                      'Friendly' name of device, MQTT topic becomes junctek/[name]/...
        -r, --retain                    Publish MQTT messages with retain flag

```

To publish to MQTT, you'll need the `Net::MQTT::Simple` Perl module installed.  
If its not available as a native package for your distro, it can be installed from CPAN e.g. `perl -MCPAN -e 'install Net::MQTT::Simple'`


