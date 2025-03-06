# spi_flash
FPGA-based FLASH emulator

This project was originally based off spispy (https://github.com/osresearch/spispy/) and still borrows some parts from it (namely, the UART stuff).

However, as spispy couldn't do what I wanted, I ended up building the SPI part from the ground up.

This design is able to keep up with a 48MHz SPI clock.

It is made for the 85k version of the ULX3S board, but could surely be backported to the smaller ULX3S versions.

I wasn't able to get the USB-CDC stuff working, but I might look into it again.

There is also a special 'log' command (0xF2) which simply forwards incoming data over the serial link. It's because I'm using this as part of a larger project (running custom code on the WiiU gamepad).

I figure this may be useful to someone else, but it's very WIP.
