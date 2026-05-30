# icepi-memtest
A memory tester for the icepi zero FPGA board. Generates and reads back a bunch of random bits at every memory address. LED 0 stays lit as long as the data read back matches the data written, and the rest of the LEDs correspond to the uppermost bits of the address.

![A photo of the icepi zero devboard with lit up LEDs, indicating the project is working.](/pictures/working.png)

Feel free to use any files I put here! I modified the icepi makefile to also traverse subdirectories, which may be of use. The controller itself is in sramInterface.sv

## How to use
This whole project uses the open source toolchain specified in [the icepi repo](https://github.com/cheyao/icepi-zero/tree/main/firmware), although not to-a-tea. I used Windows, which required some modifications that I specify below. I have to imagine for Linux the process will be smoother, although I can't speak to the specifics in that regard.

Once you are setup though, it should be as easy as just running `make` in the terminal!

### Notes on using with Windows
I used Windows and ran into some issues, so read this and avoid falling into the same traps as I! First off, with the oss-cad installation, you really do have to run `environment.bat` rather than just adding the `bin` folder to path. I thought I could get away with adding it to path, but I was mistaken and it took many hours to fix. Secondly, for the icepi device itself, I wasn't able to program it at first. The default drivers on Windows only let me communicate with the board over UART and provided no interface to program it. I ended up using [Zadig](https://zadig.akeo.ie/) to replace the driver with a generic winUSB one, which then took away UART functionality but let me program the board. In the future I hope to modify my setup to use both simultaneously, but this is the best I could achieve for now.
