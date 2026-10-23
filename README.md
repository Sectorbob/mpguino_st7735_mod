# MPGuino: Del Sol Edition ⛽🔧

*How I gave a 1995 Honda Del Sol a trip computer it never asked for.*

## The problem

The 1995 Honda Del Sol is a great little car with a removable roof and
plenty of charm. What it doesn't have is any idea how much fuel it's using.
The dashboard gives you a fuel gauge and leaves the rest to guesswork.
I wanted real numbers, so I went looking for them in the one place that
already had them: the engine computer.

## The idea

[MPGuino](http://ecomodder.com/wiki/index.php/MPGuino) is an open-source,
Arduino-based fuel economy gauge written in C. It works out mileage from two
signals the car already produces:

- **Vehicle speed sensor (VSS):** a stream of pulses whose rate tracks how
  fast the wheels are turning, which gives you **distance**.
- **Fuel injector signal:** how long the injectors stay open, which gives you
  **fuel used**.

Distance divided by fuel is miles per gallon, live, while you drive.

## The build

**Tapping the ECU.** I opened up the Del Sol's engine control unit and
soldered leads onto the VSS and fuel injector nodes. Soldering onto the
computer that keeps your engine running concentrates the mind. Measure
twice, solder once, and keep a fire extinguisher handy.

**Upgrading the display.** Stock MPGuino drives a basic character LCD.
I wanted something nicer, so I modified the firmware to drive an
**ST7735 color LCD**, with custom fonts and my own screen layouts. I mounted
it so it fits in with the instrument panel instead of looking bolted on.

**Bending the code.** Most of the work was in C: getting the display driver
working, laying out the readouts, and keeping the signal handling responsive
while the screen redraws. On a microcontroller, "just add a feature" really
means "find the RAM and the clock cycles for it first."

## What I learned

- Cars are distributed systems with worse documentation.
- Real-time signal handling and a pretty UI fight over the same few
  kilobytes of memory.
- Reading someone else's embedded C closely enough to change it safely
  is a skill in its own right.
- The car still runs. 🏁

## Stack

C · Arduino (AVR) · ST7735 TFT LCD · soldering iron · nerve

## Photos

[TODO: add photos of the ECU taps and the display in the dash]
