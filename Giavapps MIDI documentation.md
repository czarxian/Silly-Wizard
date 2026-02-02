This is a copy of the documentation for Giavapps MIDI 2, a GameMaker plug in the project uses to input and output MIDI events to MIDI devices. 

 

About MIDI Functions
 

MIDI functions use native Windows API.

Midi functions can handle multiple MIDI Input and multiple MIDI Output devices at a time.

The MIDI Input Buffers for receiving MIDI Messages have a limit of 1024 bytes.

The MIDI Output Buffer for sending MIDI Messages has no limits.

 

MIDI Input Device
 

midi_input_device_count() returns the amount of connected MIDI Input devices. This function detects connected MIDI Input devices.

 

midi_input_device_name( double DeviceIndex ) returns a string identifier for the specified MIDI Input device.

double DeviceIndex: zero-based index of the device.

 

midi_input_device_open( double DeviceIndex ) opens the specified MIDI Input device. Only open devices can receive messages.

double DeviceIndex: zero-based index of the device.

 

midi_input_device_open_all( ) opens all MIDI Input devices. Only open devices can receive messages.

 

midi_input_device_is_open( double DeviceIndex ) returns true if a MIDI Input device is open and false if not.

double DeviceIndex: zero-based index of the device.

 

midi_input_device_open_count( ) returns the amount of open MIDI Input devices.

 

midi_input_device_close( double DeviceIndex ) closes the specified MIDI Input device. Note that when you quit the application or when you unplug the device it will be closed automatically by Giavapps MIDI extension.

double DeviceIndex: zero-based index of the device.

 

midi_input_device_close_all() closes all open MIDI Input devices. Note that when you quit the application or when you unplug the device it will be closed automatically by Giavapps MIDI extension.

 

midi_input_device_connect( double InputDeviceIndex, double OutputDeviceIndex ) connects the given MIDI Input device with the specified MIDI Output device. The MIDI Input device will send all received MIDI Messages to MIDI Output device automatically.

double InputDeviceIndex: zero-based index of the device.
double OutputDeviceIndex: zero-based index of the device.

 

midi_input_device_disconnect( double InputDeviceIndex, double OutputDeviceIndex ) disconnects the given MIDI Input device from the specified MIDI Output device. Note that when you quit the application or when you unplug the device or when you close the device it will be disconnected automatically by Giavapps MIDI extension.

double InputDeviceIndex: zero-based index of the device.
double OutputDeviceIndex: zero-based index of the device.

 

midi_input_device_connection_count( double DeviceIndex ) returns the amount of connections set for the specified MIDI Input device.

double DeviceIndex: zero-based index of the device.

 

midi_input_device_connection_exists( double InputDeviceIndex, double OutputDeviceIndex ) returns true if the given MIDI Input device is connected with the specified MIDI Output device or false otherwise.

double InputDeviceIndex: zero-based index of the device.
double OutputDeviceIndex: zero-based index of the device.

 

MIDI Input Message
 

midi_input_message_manual_checking( double ManualChecking ) specifies if Giavapps MIDI should store data about detected MIDI Messages in order that you can then check that data through midi_input_message_* functions. By default this feature is disabled. When this feature is enabled you must always loop through all received data by calling midi_input_message_count() (usually inside Step event). If a MIDI device continues sending MIDI Messages and you are not processing them you may cause a memory leak. (See Code Examples below for more info about how to manual check MIDI Messages correctly). When this feature is disabled, Giavapps MIDI will stop storing data for MIDI Messages. You can leave disabled this feature if you are not going to use any of the midi_input_message_* functions.

double ManualChecking: enable (true) or disable (false) manual check.

 

midi_input_message_count( double DeviceIndex ) returns the amount of messages from the specified MIDI Input device. Use the other midi_input_message_* functions to get info about the messages. When you call this function Giavapps MIDI will free data stored for MIDI Messages (see midi_input_message_manual_checking() function for more info).

double DeviceIndex: zero-based index of the device.

 

midi_input_message_size( double DeviceIndex, double MessageIndex ) returns the amout of bytes of the specified MIDI Message.

double DeviceIndex: zero-based index of the device.
double MessageIndex: zero-based index of the MIDI Message.

 

midi_input_message_byte( double DeviceIndex, double MessageIndex, double ByteIndex) Returns the specified byte (0-255) from the given MIDI Message.

double DeviceIndex: zero-based index of the device.
double MessageIndex: zero-based index of the MIDI Message.
double ByteIndex: zero-based index of the byte.

 

midi_input_message_time( double DeviceIndex, double MessageIndex ) returns the amount of time (milliseconds) passed since the MIDI Input device was open.

double DeviceIndex: zero-based index of the device.
double MessageIndex: zero-based index of the MIDI Message.

 

MIDI Output Device
 

midi_output_device_count() returns the amount of connected MIDI Output devices. This function detects connected MIDI Output devices.

 

midi_output_device_name( double DeviceIndex ) returns a string identifier for the specified MIDI Output device.

double DeviceIndex: zero-based index of the device.

 

midi_output_device_open( double DeviceIndex ) opens the specified MIDI Output device. Only open devices can receive messages.

double DeviceIndex: zero-based index of the device.

 

midi_output_device_open_all() opens all MIDI Output devices. Only open devices can receive messages.

 

midi_output_device_is_open( double DeviceIndex ) returns true if a MIDI Output device is open and false if not.

double DeviceIndex: zero-based index of the device.

 

midi_output_device_open_count() returns the amount of open MIDI Output devices.

 

midi_output_device_close( double DeviceIndex ) closes the specified MIDI Output device. Note that when you quit the application or when you unplug the device it will be closed automatically by Giavapps MIDI extension.

double DeviceIndex: zero-based index of the device.

 

midi_output_device_close_all() closes all open MIDI Output devices. Note that when you quit the application or when you unplug the device it will be closed automatically by Giavapps MIDI extension.

 

MIDI Output Message
 

midi_output_message_clear() clears the MIDI Message Buffer. This function removes all bytes previously stored in the MIDI Message Buffer.

 

midi_output_message_size() returns the amount of bytes stored in the MIDI Message Buffer.

 

midi_output_message_byte( byte Byte ) Adds one byte to the MIDI Message Buffer.

byte Byte: value from 0 to 255.

 

midi_output_message_send( double DeviceIndex ) sends the MIDI Message Buffer previously created with midi_output_message_* functions to the specified MIDI Output device.

double DeviceIndex: zero-based index of the device.

 

midi_output_message_send_short( double DeviceIndex, double Byte1, double Byte2, double Byte3 ) sends a Short MIDI Message Buffer (up to 3 bytes) to the specified MIDI Output device. This function has lower latency. Most MIDI Messages require up to 3 bytes (except for System Exclusive MIDI Messages). If the MIDI Message requires only 2 bytes, set the Byte3 argument to 0.

double DeviceIndex: zero-based index of the device.
double Byte1: first byte.
double Byte2: second byte.
double Byte3: third byte.

 

MIDI Error
 

midi_error_manual_checking( double ManualChecking ) specifies if Giavapps MIDI should store data about detected errors in order that you can then check that data through midi_error_* functions. By default this feature is disabled. When this feature is enabled you must always loop through all received data by calling midi_error_count() (usually inside Step event). If an application continues sending errors and you are not processing them you may cause a memory leak. (See Code Examples below for more info about how to manual check errors correctly). When this feature is disabled, Giavapps MIDI will stop storing data for errors. You can leave disabled this feature if you are not going to use any of the midi_error_* functions.

double ManualChecking: enable (true) or disable (false) manual check.

 

midi_error_count() returns the amount of detected errors. Use the other midi_error_* functions to get info about the messages. When you call this function Giavapps MIDI will free data stored for errors (see midi_error_manual_checking() function for more info).

 

midi_error_string( double ErrorIndex ) returns the specified error string.

double ErrorIndex: zero-based index of the error.

 

Code Examples
 

Checking Connected MIDI Input And MIDI Output Devices
 

var str, i;
str = "MIDI INPUT DEVICES\n\n";
for(i=0; i<midi_input_device_count(); i++)
{
str += midi_input_device_name(i)+"\n";
}
show_message(str);

str = "MIDI OUTPUT DEVICES\n\n";
for(i=0; i<midi_output_device_count(); i++)
{
str += midi_output_device_name(i)+"\n";
}
show_message(str);
 

Sending Input Messages To An Output Device Automatically
 

midi_input_device_open(2);//Opens the third MIDI Input Device ("Oxygen 49" MIDI Keyboard in my case)
midi_output_device_open(0);//Opens the first MIDI Output Device ("Microsoft GS Wavetable Synth" by default on Windows)
midi_input_device_connect(2,0);//Sends all received MIDI Input Messages to the MIDI Output Device ("Oxygen 49" >>> "Microsoft GS Wavetable Synth" in my case)
 

Manual Checking MIDI Input Messages
 

Create Event

 

midi_input_message_manual_checking(1);//Enables manual checking of MIDI Messages
midi_input_device_open(2);//Opens the third MIDI Input Device ("Oxygen 49" MIDI Keyboard in my case)
 

Step Event

 

var devices, name, messages, bytes, byte, d, m, b, time, str;

devices = midi_input_device_count();

//Loops through each MIDI Input Device…
for(d = 0; d < devices; d++)
{
name = midi_input_device_name(d);

//Loops through each MIDI Input Message…
messages = midi_input_message_count(d);

for (m = 0; m < messages; m++)
{
//Composes the MIDI Input Message...
str = "MIDI INPUT MESSAGE - FROM: "+name+" - BYTES: ";
bytes = midi_input_message_size(d,m);

for(b = 0; b < bytes; b++)
{
byte = midi_input_message_byte(d,m,b);
str += string(byte)+" ";
}

time = midi_input_message_time(d, m);

str += " - TIME: "+string(time);

show_debug_message(str);
}

}
 

Sending Custom MIDI Messages To An Open Output Device
 

Create Event

 

midi_output_device_open(0);//Opens the first MIDI Output Device ("Microsoft GS Wavetable Synth" by default on Windows)
 

Step Event

 

if(keyboard_check_pressed(vk_space))
{
//NOTE C5 ON – CHANNEL 1 – VELOCITY 127
midi_output_message_clear();//Clears the MIDI Message buffer
midi_output_message_byte(144);//Adds one byte to the MIDI Message buffer
midi_output_message_byte(60);//Adds one byte to the MIDI Message buffer
midi_output_message_byte(127);//Adds one byte to the MIDI Message buffer
midi_output_message_send(0);//Sends the MIDI Message to the MIDI Output Device
}
else if(keyboard_check_released(vk_space))
{
//NOTE C5 OFF – CHANNEL 1 – VELOCITY 0
midi_output_message_clear();//Clears the MIDI Message buffer
midi_output_message_byte(128);//Adds one byte to the MIDI Message buffer
midi_output_message_byte(60);//Adds one byte to the MIDI Message buffer
midi_output_message_byte(0);//Adds one byte to the MIDI Message buffer
midi_output_message_send(0);//Sends the MIDI Message to the MIDI Output Device
}

//LOW LATENCY VERSION

if(keyboard_check_pressed(vk_enter))
{
//NOTE C5 ON – CHANNEL 1 – VELOCITY 127
midi_output_message_send_short(0, 144, 60, 127);//Sends the MIDI Message to the MIDI Output Device
}
else if(keyboard_check_released(vk_enter))
{
//NOTE C5 OFF – CHANNEL 1 – VELOCITY 0
midi_output_message_send_short(0, 128, 60, 0);//Sends the MIDI Message to the MIDI Output Device
}
 

Manual Checking MIDI Errors
 

Create Event

 

midi_error_manual_checking(1);//Enables manual checking of MIDI errors
 

Step Event

 

//CHECKING MIDI ERRORS
var errors, e;
errors = midi_error_count();
for(e=0; e<errors; e++)
{
show_debug_message(midi_error_string(e));
}
 