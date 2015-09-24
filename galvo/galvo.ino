/** \file
 * Vector display using the MCP4921 DAC on the teensy3.1.
 *
 * this uses the DMA hardware to drive the SPI output and
 * the second chip select pin (6) to enable/disable the beam.
 *
 * format of commands is 3-bytes per command.
 * 2 bits
 *  00 == number of lines to be sent
 *  01 == "pen up" move to new X,Y
 *  10 == normal line to X,Y
 *  11 == bright line to X,Y
 * 11 bits of X (or number of lines)
 * 11 bits of Y
 */
#include <SPI.h>
#include "DMAChannel.h"

#define SS_PIN	10
#define SS2_PIN	6
#define SDI	11
#define SCK	13

#define RED_PIN	3
#define DEBUG_PIN	8
#define DELAY_PIN	9

#define MAX_PTS 1024
static unsigned rx_points;
static unsigned num_points;
static unsigned fb;
static uint16_t points[2][MAX_PTS][2];
static unsigned do_resync;

#define MOVETO		(1<<11)
#define LINETO		(2<<11)
#define BRIGHTTO	(3<<11)


static DMAChannel spi_dma;
#define SPI_DMA_MAX 4096
static uint32_t spi_dma_q[2][SPI_DMA_MAX];
static unsigned spi_dma_which;
static unsigned spi_dma_count;
static unsigned spi_dma_in_progress;
static unsigned spi_dma_cs; // which pins are we using for IO


static int
spi_dma_tx_append(
	uint16_t value
)
{
	spi_dma_q[spi_dma_which][spi_dma_count++] = 0
		| ((uint32_t) value)
		| (spi_dma_cs << 16) // enable the chip select line
		;

	if (spi_dma_count == SPI_DMA_MAX)
		return 1;
	return 0;
}


static void
spi_dma_tx()
{
	if (spi_dma_count == 0)
		return;

	// add a EOQ to the last entry
	spi_dma_q[spi_dma_which][spi_dma_count-1] |= (1<<27);

	spi_dma.clearComplete();
	spi_dma.clearError();
	spi_dma.sourceBuffer(
		spi_dma_q[spi_dma_which],
		4 * spi_dma_count  // in bytes, not thingies
	);

	spi_dma_which = !spi_dma_which;
	spi_dma_count = 0;

	SPI0_SR = 0xFF0F0000;
	SPI0_RSER = 0
		| SPI_RSER_RFDF_RE
		| SPI_RSER_RFDF_DIRS
		| SPI_RSER_TFFF_RE
		| SPI_RSER_TFFF_DIRS;

	spi_dma.enable();
	spi_dma_in_progress = 1;
}


static int
spi_dma_tx_complete()
{
	cli();

	// if nothing is in progress, we're "complete"
	if (!spi_dma_in_progress)
	{
		sei();
		return 1;
	}

	if (!spi_dma.complete())
	{
		sei();
		return 0;
	}

	digitalWriteFast(DELAY_PIN, 1);

	spi_dma.clearComplete();
	spi_dma.clearError();

	// the DMA hardware lies; it is not actually complete
	delayMicroseconds(5);
	digitalWriteFast(DELAY_PIN, 0);
	sei();

	// we are done!
	SPI0_RSER = 0;
	SPI0_SR = 0xFF0F0000;
	spi_dma_in_progress = 0;
	return 1;
}


static void
spi_dma_setup()
{
	spi_dma.disable();
	spi_dma.destination((volatile uint32_t&) SPI0_PUSHR);
	spi_dma.disableOnCompletion();
	spi_dma.triggerAtHardwareEvent(DMAMUX_SOURCE_SPI0_TX);
	spi_dma.transferSize(4); // write all 32-bits of PUSHR

	SPI.beginTransaction(SPISettings(20000000, MSBFIRST, SPI_MODE0));

	// configure the output on pin 10 for !SS0 from the SPI hardware
	// and pin 6 for !SS1.
	CORE_PIN10_CONFIG = PORT_PCR_DSE | PORT_PCR_MUX(2);
	CORE_PIN6_CONFIG = PORT_PCR_DSE | PORT_PCR_MUX(2);

	// configure the frame size for 16-bit transfers
	SPI0_CTAR0 |= 0xF << 27;

	// send something to get it started
	spi_dma_which = 0;
	spi_dma_count = 0;

	spi_dma_tx_append(0);
	spi_dma_tx_append(0);
	spi_dma_tx();
}



void
setup()
{
	Serial.begin(9600);
	pinMode(RED_PIN, OUTPUT);
	pinMode(DEBUG_PIN, OUTPUT);
	pinMode(DELAY_PIN, OUTPUT);
	digitalWrite(RED_PIN, 0);
	digitalWrite(DEBUG_PIN, 0);

	pinMode(SS_PIN, OUTPUT);
	pinMode(SS2_PIN, OUTPUT);
	pinMode(SDI, OUTPUT);
	pinMode(SCK, OUTPUT);

	// fill in some points so that we don't burn in the beam
	points[0][0][0] = 0 | MOVETO;
	points[0][0][1] = 0;
	points[0][1][0] = 2047 | LINETO;
	points[0][1][1] = 0;
	points[0][2][0] = 2047 | LINETO;
	points[0][2][1] = 2047;
	points[0][3][0] = 0 | LINETO;
	points[0][3][1] = 2047;
	points[0][4][0] = 0 | LINETO;
	points[0][4][1] = 0;
	points[0][5][0] = 1024 | BRIGHTTO;
	points[0][5][1] = 2047;
	points[0][6][0] = 2047 | BRIGHTTO;
	points[0][6][1] = 1024;
	points[0][7][0] = 0 | BRIGHTTO;
	points[0][7][1] = 0;
	points[0][8][0] = 2047 | LINETO;
	points[0][8][1] = 512;
	points[0][9][0] = 0 | MOVETO;
	points[0][9][1] = 0;
	points[0][10][0] = 2047 | LINETO;
	points[0][10][1] = 256;
	num_points = 11;
	

#ifdef SLOW_SPI
	SPI.begin();
	SPI.setClockDivider(SPI_CLOCK_DIV2);
#else
	//spi4teensy3::init(0);
	SPI.begin();
	SPI.setClockDivider(SPI_CLOCK_DIV2);

	//DMASPI0.begin();
	//DMASPI0.start();
	spi_dma_setup();
#endif
}


static void
mpc4921_write(
	int channel,
	uint16_t value
)
{
	value &= 0x0FFF; // mask out just the 12 bits of data

	// select the output channel, buffered, no gain
	value |= 0x7000 | (channel == 1 ? 0x8000 : 0x0000);

#ifdef SLOW_SPI
	SPI.transfer((value >> 8) & 0xFF);
	SPI.transfer((value >> 0) & 0xFF);
#else
	if (spi_dma_tx_append(value) == 0)
		return;

	// wait for the previous line to finish
	while(!spi_dma_tx_complete())
		;

	// now send this line, which swaps buffers
	spi_dma_tx();
#endif
}




// x and y position are in 11-bit range
static uint16_t x_pos;
static uint16_t y_pos;

static inline void
goto_x(
	uint16_t x
)
{
	x_pos = x;
	mpc4921_write(1, x);
}

static inline void
goto_y(
	uint16_t y
)
{
	y_pos = y;
	mpc4921_write(0, y);
}


static inline void
_lineto(
	int x1,
	int y1,
	const int bright_shift
)
{
	int dx;
	int dy;
	int sx;
	int sy;

	const int x1_orig = x1;
	const int y1_orig = y1;

	int x_off = x1 & ((1 << bright_shift) - 1);
	int y_off = y1 & ((1 << bright_shift) - 1);
	x1 >>= bright_shift;
	y1 >>= bright_shift;
	int x0 = x_pos >> bright_shift;
	int y0 = y_pos >> bright_shift;

	if (x0 <= x1)
	{
		dx = x1 - x0;
		sx = 1;
	} else {
		dx = x0 - x1;
		sx = -1;
	}

	if (y0 <= y1)
	{
		dy = y1 - y0;
		sy = 1;
	} else {
		dy = y0 - y1;
		sy = -1;
	}

	int err = dx - dy;

	while (1)
	{
		if (x0 == x1 && y0 == y1)
			break;

		int e2 = 2 * err;
		if (e2 > -dy)
		{
			err = err - dy;
			x0 += sx;
			goto_x(x_off + (x0 << bright_shift));
		}
		if (e2 < dx)
		{
			err = err + dx;
			y0 += sy;
			goto_y(y_off + (y0 << bright_shift));
		}
	}

	// ensure that we end up exactly where we want
	goto_x(x1_orig);
	goto_y(y1_orig);

/*
	// wait for the previous line to finish
	while(!spi_dma_tx_complete())
		;

	// now send this line, which swaps buffers
	spi_dma_tx();
*/
}


void
lineto(
	int x1,
	int y1
)
{
	_lineto(x1, y1, 2);
}


void
lineto_bright(
	int x1,
	int y1
)
{
	_lineto(x1, y1, 0);
}

void
lineto_off(
	int x1,
	int y1
)
{
	spi_dma_cs=3;
	_lineto(x1, y1, 5);
	spi_dma_cs=1;
}

uint8_t
read_blocking()
{
	while(1)
	{
		int c = Serial.read();
		if (c >= 0)
			return c;
	}
}


static int
read_data()
{
	static uint32_t cmd;
	static unsigned offset;

	int c = Serial.read();
	if (c < 0)
		return -1;

	//Serial.print("----- read: ");
	//Serial.println(c);

	// if we are resyncing, wait for a non-zero byte
	if (do_resync)
	{
		if (c == 0)
			return 0;
		do_resync = 0;
	}

	cmd = (cmd << 8) | c;
	offset++;

	if (offset != 3)
		return 0;

	// we have a new command
	// check for a resync
	if (cmd == 0)
	{
		do_resync = 1;
		offset = cmd = 0;
		return 0;
	}

	unsigned bright	= (cmd >> 22) & 0x3;
	unsigned x	= (cmd >> 11) & 0x7FF;
	unsigned y	= (cmd >> 0) & 0x7FF;

	offset = cmd = 0;

	// bright 0, switch buffers
	if (bright == 0)
	{
		fb = !fb;
		num_points = rx_points;
		rx_points = 0;

		//Serial.print("*** fb");
		//Serial.print(fb);
		//Serial.print(" ");
		//Serial.println(num_points);
		return 1;
	}

	uint16_t * pt = points[!fb][rx_points++];
	pt[0] = x | (bright << 11);
	pt[1] = y;

	return 0;
}


void
loop()
{
	//Serial.print(fb);
	//Serial.print(' ');
	//Serial.print(num_points);
	//Serial.println();

	read_data();

	digitalWrite(DEBUG_PIN, 1);

	for(unsigned n = 0 ; n < num_points ; n++)
	{
		if (Serial.available())
		{
			for (int j = 0 ; j < 8 ; j++)
			{
				int rc = read_data();
				if (rc < 0)
					break;

				// buffer switch!
				if (rc == 1)
				{
					digitalWrite(RED_PIN, 0);
					n = 0;
					;return;
				}
			}
		}

		const uint16_t * const pt = points[fb][n];
		uint16_t x = pt[0];
		uint16_t y = pt[1];
		unsigned intensity = (x >> 11) & 0x3;
		x = (x & 0x7FF) << 1;
		y = (y & 0x7FF) << 1;

#if 0
		Serial.print(x);
		Serial.print(' ');
		Serial.print(y);
		Serial.print(' ');
		Serial.println(intensity);
#endif

		if (intensity == 1)
			lineto_off(x,y);
		else
		if (intensity == 2)
			lineto(x, y);
		else
			lineto_bright(x, y);

		digitalWrite(DEBUG_PIN, 0);
	}
}

