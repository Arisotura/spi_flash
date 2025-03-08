# spi_flash
FPGA-based FLASH emulator

This project was originally based off spispy (https://github.com/osresearch/spispy/) and still borrows some parts from it (namely, the UART stuff).

However, as spispy couldn't do what I wanted, I ended up building the SPI part from the ground up.

This design is able to keep up with a 48 MHz SPI clock.

It is made for the 85k version of the ULX3S board, but could surely be backported to the smaller ULX3S versions.

I wasn't able to get the USB-CDC stuff working, but I might look into it again.

There is also a special 'log' command (0xF2) which simply forwards incoming data over the serial link. It's because I'm using this as part of a larger project (running custom code on the WiiU gamepad).

I figure this may be useful to someone else, but it's very WIP.


## Serial protocol

A 3M baud serial interface is exposed over the US1 port. Settings are 8 data bits, one stop bit, no parity.

The following commands are available:

0x30: get protocol version (currently 1)

0x31: read data from SDRAM

0x32: write data to SDRAM

Read and write commands are followed by four bytes: first 3 bytes are the address (MSB first) and last byte is the length to read/write. Address and length are expressed in 8-byte units.

Read commands will then return the requested data.

Write commands are followed by the data to be written. A 0x01 byte is sent to indicate write completion.

The serial interface should not be used while the SPI bus is active.


## Modules

top.v: 'top' module, interconnecting everything

spi_trx.v: handles SPI communication and base logic

glue.v: handles the serial protocol and SPI erase/page program commands (read commands are directly sent to the SDRAM controller)

sdram.v: SDRAM controller

uart.v: serial interface (over US1)


## Technical details

This project is built to emulate a 32MB SPI FLASH, like the Micron N25Q256A.

The N25Q256A supports a 4-byte addressing mode allowing to access the entire 32MB range. spi_flash supports both 3-byte and 4-byte addressing.

Supporting different types/sizes of FLASH chips will require adjustments to the code. Supporting higher capacities than 32MB would require using a different FPGA board with more RAM.

This design could probably support higher clock speeds than 48 MHz, with revisions to spi_trx.v. 

Dual and quad SPI modes aren't supported. They should also be doable, but I have no test case for them.

Different types/sizes of FLASH memory may have different layouts, which would imply that erase and page program commands would operate on different quantities. Adjusting to that will require changes to the code.

spi_trx sets write_addr and write_len when signalling a write operation to the glue module. write_len is the total length to write minus one, expressed in 8-byte units. For example a value of 0x1F means to write 256 bytes. write_addr should be aligned to a similar boundary, ie. during a page program command, it will be set to the beginning of the page.

For page program commands, the glue module keeps a page-sized buffer to receive the data to be programmed. When CS goes high, the write buffer is committed to SDRAM. Supporting a different page size will require adjusting the size of this buffer.

The SDRAM controller operates in terms of 8-byte bursts. This burst length was chosen because it provides the best tradeoff when handling SPI read commands. The controller logic was made to support other burst lengths, but doing so will require code adjustments. 

Porting this design to a different FPGA board may require a different RAM controller, depending on what kind of RAM it has. The SDRAM controller in this design is pretty simple, so this shouldn't be overwhelmingly difficult.
