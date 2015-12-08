/** \file
 * V.st vector board interface
 */
import processing.serial.*;

Serial vector_serial; 

static byte[] bytes = new byte[8192];
static int byte_count = 0;
static int last_x;
static int last_y;

// first 2 brightness, next 11 X-coord, last 11 Y-coord;
// 3 x 8 bit bytes

void
vector_setup()
{
	// finding the right port requires picking it from the list
	// should look for one that matches "ttyACM*" or "tty.usbmodem*"
	for(String port : Serial.list())
	{
		println(port);
		if (match(port, "usbmode|ACM") == null)
			continue;
		vector_serial = new Serial(this, port, 9600); 
		return;
	}
  
	println("No valid serial ports found?\n");
}


boolean
vector_offscreen(
	float x,
	float y
)
{
	return (x < 0 || x >= width || y < 0 || y >= height);
}


void
vector_line(
	boolean bright,
	float x0,
	float y0,
	float x1,
	float y1
)
{
	stroke(bright ? 255 : 120);
	line(x0, y0, x1, y1);

	// there are five possibilities:
	// x0,y0 and x1,y1 are in the screen.
	// x0,y0 is off screen, and x1,y1 is on screen
	// x0,y0 is on screen, and x1,y1 is off screen
	// both are off screen (and cross the display)
	// both are off screen (and nothing to see)

/*
	// if both x0,x1 or y0,y1 lie off screen on the same side,
	// there are no intersections.
	if ((x0 < 0 && x1 < 0)
	||  (x0 >= width && x1 >= width)
	||  (y0 < 0 && y1 < 0)
	||  (y0 >= height && y1 >= height))
		return;
*/

	// should compute point of crossing the boundary
	if (vector_offscreen(x0,y0)
	||  vector_offscreen(x1,y1))
	{
		//
		return;
	}

	vector_point(1, x0, y0);
	vector_point(bright ? 3 : 2, x1, y1);
}


void
vector_point(
	int bright,
	float xf,
	float yf
)
{
	// Vector axis is (0,0) in the bottom left corner;
	// this needs to flip the Y axis.
	int x = (int)(xf * 2047 / width);
	int y = 2047 - (int)(yf * 2047 / height);

	// skip the transit if we are going to the same point
	if (x == last_x && y == last_y)
		return;

	last_x = x;
	last_y = y;

	int cmd = (bright & 3) << 22 | (x & 2047) << 11 | (y & 2047) << 0;
	bytes[byte_count++] = (byte)((cmd >> 16) & 0xFF);
	bytes[byte_count++] = (byte)((cmd >>  8) & 0xFF);
	bytes[byte_count++] = (byte)((cmd >>  0) & 0xFF);
}


void vector_send()
{
	// add the "draw frame" command
	bytes[byte_count++] = 1;
	bytes[byte_count++] = 1;
	bytes[byte_count++] = 1;

	if (vector_serial != null)
		vector_serial.write(subset(bytes, 0, byte_count));

	// reset the output buffer
	byte_count = 0;

	bytes[byte_count++] = 0;
	bytes[byte_count++] = 0;
	bytes[byte_count++] = 0;
	bytes[byte_count++] = 0;
}


/*
 * Complete ASCII Hershey Simplex font.
 *
 * http://paulbourke.net/dataformats/hershey/
 *
 * A few characters are simplified and all are stored at
 * offset ' ' (0x20).
 */

class HersheyChar
{
	HersheyChar(int w, int[] p)
	{
		width = w;
		points = p;
	}

	final int width;
	final int[] points;

	float draw(float x, float y, float size, boolean bright)
	{
		boolean moveto = true;
		float ox = x;
		float oy = y;

		for(int i = 0 ; i < points.length ; i += 2)
		{
			int dx = points[i+0];
			int dy = points[i+1];

			if (dx == -1 && dy == -1)
			{
				moveto = true;
				continue;
			}

 			float nx = x + (dx * size) / 16.0;
			float ny = y - (dy * size) / 16.0;

			if (!moveto)
				vector_line(bright, ox, oy, nx, ny);

			ox = nx;
			oy = ny;

			moveto = false;
		}

		return width * size / 16.0;
	}

};

float
vector_string(
	String s,
	float x,
	float y,
	float size,
	boolean bright
) {
	for(char c : s.toCharArray())
	{
		HersheyChar hc = hershey_font[c - 0x20];
		x += hc.draw(x, y, size, bright);
	}

	return x;
}

HersheyChar[] hershey_font = new HersheyChar[]{
    new HersheyChar(16, new int[]{
    }),
    new HersheyChar(10, new int[]{
        5,21, 5,7, -1,-1, 5,2, 4,1, 5,0, 6,1, 5,2,
    }),
    new HersheyChar(16, new int[]{
        4,21, 4,14, -1,-1, 12,21, 12,14,
    }),
    new HersheyChar(21, new int[]{
        11,25, 4,-7, -1,-1, 17,25, 10,-7, -1,-1, 4,12, 18,12, -1,-1, 3,6, 17,6,
    }),
    new HersheyChar(20, new int[]{
        8,25, 8,-4, -1,-1, 12,25, 12,-4, -1,-1, 17,18, 15,20, 12,21, 8,21, 5,20, 3,18, 3,16, 4,14, 5,13, 7,12, 13,10, 15,9, 16,8, 17,6, 17,3, 15,1, 12,0, 8,0, 5,1, 3,3,
    }),
    new HersheyChar(24, new int[]{
        21,21, 3,0, -1,-1, 8,21, 10,19, 10,17, 9,15, 7,14, 5,14, 3,16, 3,18, 4,20, 6,21, 8,21, 10,20, 13,19, 16,19, 19,20, 21,21, -1,-1, 17,7, 15,6, 14,4, 14,2, 16,0, 18,0, 20,1, 21,3, 21,5, 19,7, 17,7,
    }),
    new HersheyChar(26, new int[]{
        23,12, 23,13, 22,14, 21,14, 20,13, 19,11, 17,6, 15,3, 13,1, 11,0, 7,0, 5,1, 4,2, 3,4, 3,6, 4,8, 5,9, 12,13, 13,14, 14,16, 14,18, 13,20, 11,21, 9,20, 8,18, 8,16, 9,13, 11,10, 16,3, 18,1, 20,0, 22,0, 23,1, 23,2,
    }),
    new HersheyChar(10, new int[]{
        5,19, 4,20, 5,21, 6,20, 6,18, 5,16, 4,15,
    }),
    new HersheyChar(14, new int[]{
        11,25, 9,23, 7,20, 5,16, 4,11, 4,7, 5,2, 7,-2, 9,-5, 11,-7,
    }),
    new HersheyChar(14, new int[]{
        3,25, 5,23, 7,20, 9,16, 10,11, 10,7, 9,2, 7,-2, 5,-5, 3,-7,
    }),
    new HersheyChar(16, new int[]{
        8,21, 8,9, -1,-1, 3,18, 13,12, -1,-1, 13,18, 3,12,
    }),
    new HersheyChar(26, new int[]{
        13,18, 13,0, -1,-1, 4,9, 22,9,
    }),
    new HersheyChar(10, new int[]{
        6,1, 5,0, 4,1, 5,2, 6,1, 6,-1, 5,-3, 4,-4,
    }),
    new HersheyChar(26, new int[]{
        4,9, 22,9,
    }),
    new HersheyChar(10, new int[]{
        5,2, 4,1, 5,0, 6,1, 5,2,
    }),
    new HersheyChar(22, new int[]{
        20,25, 2,-7,
    }),
    new HersheyChar(20, new int[]{
        9,21, 6,20, 4,17, 3,12, 3,9, 4,4, 6,1, 9,0, 11,0, 14,1, 16,4, 17,9, 17,12, 16,17, 14,20, 11,21, 9,21,
    }),
    new HersheyChar(20, new int[]{
        6,17, 8,18, 11,21, 11,0,
    }),
    new HersheyChar(20, new int[]{
        4,16, 4,17, 5,19, 6,20, 8,21, 12,21, 14,20, 15,19, 16,17, 16,15, 15,13, 13,10, 3,0, 17,0,
    }),
    new HersheyChar(20, new int[]{
        5,21, 16,21, 10,13, 13,13, 15,12, 16,11, 17,8, 17,6, 16,3, 14,1, 11,0, 8,0, 5,1, 4,2, 3,4,
    }),
    new HersheyChar(20, new int[]{
        13,21, 3,7, 18,7, -1,-1, 13,21, 13,0,
    }),
    new HersheyChar(20, new int[]{
        15,21, 5,21, 4,12, 5,13, 8,14, 11,14, 14,13, 16,11, 17,8, 17,6, 16,3, 14,1, 11,0, 8,0, 5,1, 4,2, 3,4,
    }),
    new HersheyChar(20, new int[]{
        16,18, 15,20, 12,21, 10,21, 7,20, 5,17, 4,12, 4,7, 5,3, 7,1, 10,0, 11,0, 14,1, 16,3, 17,6, 17,7, 16,10, 14,12, 11,13, 10,13, 7,12, 5,10, 4,7,
    }),
    new HersheyChar(20, new int[]{
        17,21, 7,0, -1,-1, 3,21, 17,21,
    }),
    new HersheyChar(20, new int[]{
        8,21, 5,20, 4,18, 4,16, 5,14, 7,13, 11,12, 14,11, 16,9, 17,7, 17,4, 16,2, 15,1, 12,0, 8,0, 5,1, 4,2, 3,4, 3,7, 4,9, 6,11, 9,12, 13,13, 15,14, 16,16, 16,18, 15,20, 12,21, 8,21,
    }),
    new HersheyChar(20, new int[]{
        16,14, 15,11, 13,9, 10,8, 9,8, 6,9, 4,11, 3,14, 3,15, 4,18, 6,20, 9,21, 10,21, 13,20, 15,18, 16,14, 16,9, 15,4, 13,1, 10,0, 8,0, 5,1, 4,3,
    }),
    new HersheyChar(10, new int[]{
        5,14, 4,13, 5,12, 6,13, 5,14, -1,-1, 5,2, 4,1, 5,0, 6,1, 5,2,
    }),
    new HersheyChar(10, new int[]{
        5,14, 4,13, 5,12, 6,13, 5,14, -1,-1, 6,1, 5,0, 4,1, 5,2, 6,1, 6,-1, 5,-3, 4,-4,
    }),
    new HersheyChar(24, new int[]{
        20,18, 4,9, 20,0,
    }),
    new HersheyChar(26, new int[]{
        4,12, 22,12, -1,-1, 4,6, 22,6,
    }),
    new HersheyChar(24, new int[]{
        4,18, 20,9, 4,0,
    }),
    new HersheyChar(18, new int[]{
        3,16, 3,17, 4,19, 5,20, 7,21, 11,21, 13,20, 14,19, 15,17, 15,15, 14,13, 13,12, 9,10, 9,7, -1,-1, 9,2, 8,1, 9,0, 10,1, 9,2,
    }),
    new HersheyChar(27, new int[]{
        18,13, 17,15, 15,16, 12,16, 10,15, 9,14, 8,11, 8,8, 9,6, 11,5, 14,5, 16,6, 17,8, -1,-1, 12,16, 10,14, 9,11, 9,8, 10,6, 11,5, -1,-1, 18,16, 17,8, 17,6, 19,5, 21,5, 23,7, 24,10, 24,12, 23,15, 22,17, 20,19, 18,20, 15,21, 12,21, 9,20, 7,19, 5,17, 4,15, 3,12, 3,9, 4,6, 5,4, 7,2, 9,1, 12,0, 15,0, 18,1, 20,2, 21,3, -1,-1, 19,16, 18,8, 18,6, 19,5,
    }),
    new HersheyChar(18, new int[]{
        9,21, 1,0, -1,-1, 9,21, 17,0, -1,-1, 4,7, 14,7,
    }),
    new HersheyChar(21, new int[]{
        4,21, 4,0, -1,-1, 4,21, 13,21, 16,20, 17,19, 18,17, 18,15, 17,13, 16,12, 13,11, -1,-1, 4,11, 13,11, 16,10, 17,9, 18,7, 18,4, 17,2, 16,1, 13,0, 4,0,
    }),
    new HersheyChar(21, new int[]{
        18,16, 17,18, 15,20, 13,21, 9,21, 7,20, 5,18, 4,16, 3,13, 3,8, 4,5, 5,3, 7,1, 9,0, 13,0, 15,1, 17,3, 18,5,
    }),
    new HersheyChar(21, new int[]{
        4,21, 4,0, -1,-1, 4,21, 11,21, 14,20, 16,18, 17,16, 18,13, 18,8, 17,5, 16,3, 14,1, 11,0, 4,0,
    }),
    new HersheyChar(19, new int[]{
        4,21, 4,0, -1,-1, 4,21, 17,21, -1,-1, 4,11, 12,11, -1,-1, 4,0, 17,0,
    }),
    new HersheyChar(18, new int[]{
        4,21, 4,0, -1,-1, 4,21, 17,21, -1,-1, 4,11, 12,11,
    }),
    new HersheyChar(21, new int[]{
        18,16, 17,18, 15,20, 13,21, 9,21, 7,20, 5,18, 4,16, 3,13, 3,8, 4,5, 5,3, 7,1, 9,0, 13,0, 15,1, 17,3, 18,5, 18,8, -1,-1, 13,8, 18,8,
    }),
    new HersheyChar(22, new int[]{
        4,21, 4,0, -1,-1, 18,21, 18,0, -1,-1, 4,11, 18,11,
    }),
    new HersheyChar(8, new int[]{
        4,21, 4,0,
    }),
    new HersheyChar(16, new int[]{
        12,21, 12,5, 11,2, 10,1, 8,0, 6,0, 4,1, 3,2, 2,5, 2,7,
    }),
    new HersheyChar(21, new int[]{
        4,21, 4,0, -1,-1, 18,21, 4,7, -1,-1, 9,12, 18,0,
    }),
    new HersheyChar(17, new int[]{
        4,21, 4,0, -1,-1, 4,0, 16,0,
    }),
    new HersheyChar(24, new int[]{
        4,21, 4,0, -1,-1, 4,21, 12,0, -1,-1, 20,21, 12,0, -1,-1, 20,21, 20,0,
    }),
    new HersheyChar(22, new int[]{
        4,21, 4,0, -1,-1, 4,21, 18,0, -1,-1, 18,21, 18,0,
    }),
    new HersheyChar(22, new int[]{
        9,21, 7,20, 5,18, 4,16, 3,13, 3,8, 4,5, 5,3, 7,1, 9,0, 13,0, 15,1, 17,3, 18,5, 19,8, 19,13, 18,16, 17,18, 15,20, 13,21, 9,21,
    }),
    new HersheyChar(21, new int[]{
        4,21, 4,0, -1,-1, 4,21, 13,21, 16,20, 17,19, 18,17, 18,14, 17,12, 16,11, 13,10, 4,10,
    }),
    new HersheyChar(22, new int[]{
        9,21, 7,20, 5,18, 4,16, 3,13, 3,8, 4,5, 5,3, 7,1, 9,0, 13,0, 15,1, 17,3, 18,5, 19,8, 19,13, 18,16, 17,18, 15,20, 13,21, 9,21, -1,-1, 12,4, 18,-2,
    }),
    new HersheyChar(21, new int[]{
        4,21, 4,0, -1,-1, 4,21, 13,21, 16,20, 17,19, 18,17, 18,15, 17,13, 16,12, 13,11, 4,11, -1,-1, 11,11, 18,0,
    }),
    new HersheyChar(20, new int[]{
        17,18, 15,20, 12,21, 8,21, 5,20, 3,18, 3,16, 4,14, 5,13, 7,12, 13,10, 15,9, 16,8, 17,6, 17,3, 15,1, 12,0, 8,0, 5,1, 3,3,
    }),
    new HersheyChar(16, new int[]{
        8,21, 8,0, -1,-1, 1,21, 15,21,
    }),
    new HersheyChar(22, new int[]{
        4,21, 4,6, 5,3, 7,1, 10,0, 12,0, 15,1, 17,3, 18,6, 18,21,
    }),
    new HersheyChar(18, new int[]{
        1,21, 9,0, -1,-1, 17,21, 9,0,
    }),
    new HersheyChar(24, new int[]{
        2,21, 7,0, -1,-1, 12,21, 7,0, -1,-1, 12,21, 17,0, -1,-1, 22,21, 17,0,
    }),
    new HersheyChar(20, new int[]{
        3,21, 17,0, -1,-1, 17,21, 3,0,
    }),
    new HersheyChar(18, new int[]{
        1,21, 9,11, 9,0, -1,-1, 17,21, 9,11,
    }),
    new HersheyChar(20, new int[]{
        17,21, 3,0, -1,-1, 3,21, 17,21, -1,-1, 3,0, 17,0,
    }),
    new HersheyChar(14, new int[]{
        4,25, 4,-7, -1,-1, 5,25, 5,-7, -1,-1, 4,25, 11,25, -1,-1, 4,-7, 11,-7,
    }),
    new HersheyChar(14, new int[]{
        0,21, 14,-3,
    }),
    new HersheyChar(14, new int[]{
        9,25, 9,-7, -1,-1, 10,25, 10,-7, -1,-1, 3,25, 10,25, -1,-1, 3,-7, 10,-7,
    }),
    new HersheyChar(16, new int[]{
        6,15, 8,18, 10,15, -1,-1, 3,12, 8,17, 13,12, -1,-1, 8,17, 8,0,
    }),
    new HersheyChar(16, new int[]{
        0,-2, 16,-2,
    }),
    new HersheyChar(10, new int[]{
        6,21, 5,20, 4,18, 4,16, 5,15, 6,16, 5,17,
    }),
    new HersheyChar(19, new int[]{
        15,14, 15,0, -1,-1, 15,11, 13,13, 11,14, 8,14, 6,13, 4,11, 3,8, 3,6, 4,3, 6,1, 8,0, 11,0, 13,1, 15,3,
    }),
    new HersheyChar(19, new int[]{
        4,21, 4,0, -1,-1, 4,11, 6,13, 8,14, 11,14, 13,13, 15,11, 16,8, 16,6, 15,3, 13,1, 11,0, 8,0, 6,1, 4,3,
    }),
    new HersheyChar(18, new int[]{
        15,11, 13,13, 11,14, 8,14, 6,13, 4,11, 3,8, 3,6, 4,3, 6,1, 8,0, 11,0, 13,1, 15,3,
    }),
    new HersheyChar(19, new int[]{
        15,21, 15,0, -1,-1, 15,11, 13,13, 11,14, 8,14, 6,13, 4,11, 3,8, 3,6, 4,3, 6,1, 8,0, 11,0, 13,1, 15,3,
    }),
    new HersheyChar(18, new int[]{
        3,8, 15,8, 15,10, 14,12, 13,13, 11,14, 8,14, 6,13, 4,11, 3,8, 3,6, 4,3, 6,1, 8,0, 11,0, 13,1, 15,3,
    }),
    new HersheyChar(12, new int[]{
        10,21, 8,21, 6,20, 5,17, 5,0, -1,-1, 2,14, 9,14,
    }),
    new HersheyChar(19, new int[]{
        15,14, 15,-2, 14,-5, 13,-6, 11,-7, 8,-7, 6,-6, -1,-1, 15,11, 13,13, 11,14, 8,14, 6,13, 4,11, 3,8, 3,6, 4,3, 6,1, 8,0, 11,0, 13,1, 15,3,
    }),
    new HersheyChar(19, new int[]{
        4,21, 4,0, -1,-1, 4,10, 7,13, 9,14, 12,14, 14,13, 15,10, 15,0,
    }),
    new HersheyChar(8, new int[]{
        3,21, 4,20, 5,21, 4,22, 3,21, -1,-1, 4,14, 4,0,
    }),
    new HersheyChar(10, new int[]{
        5,21, 6,20, 7,21, 6,22, 5,21, -1,-1, 6,14, 6,-3, 5,-6, 3,-7, 1,-7,
    }),
    new HersheyChar(17, new int[]{
        4,21, 4,0, -1,-1, 14,14, 4,4, -1,-1, 8,8, 15,0,
    }),
    new HersheyChar(8, new int[]{
        4,21, 4,0,
    }),
    new HersheyChar(30, new int[]{
        4,14, 4,0, -1,-1, 4,10, 7,13, 9,14, 12,14, 14,13, 15,10, 15,0, -1,-1, 15,10, 18,13, 20,14, 23,14, 25,13, 26,10, 26,0,
    }),
    new HersheyChar(19, new int[]{
        4,14, 4,0, -1,-1, 4,10, 7,13, 9,14, 12,14, 14,13, 15,10, 15,0,
    }),
    new HersheyChar(19, new int[]{
        8,14, 6,13, 4,11, 3,8, 3,6, 4,3, 6,1, 8,0, 11,0, 13,1, 15,3, 16,6, 16,8, 15,11, 13,13, 11,14, 8,14,
    }),
    new HersheyChar(19, new int[]{
        4,14, 4,-7, -1,-1, 4,11, 6,13, 8,14, 11,14, 13,13, 15,11, 16,8, 16,6, 15,3, 13,1, 11,0, 8,0, 6,1, 4,3,
    }),
    new HersheyChar(19, new int[]{
        15,14, 15,-7, -1,-1, 15,11, 13,13, 11,14, 8,14, 6,13, 4,11, 3,8, 3,6, 4,3, 6,1, 8,0, 11,0, 13,1, 15,3,
    }),
    new HersheyChar(13, new int[]{
        4,14, 4,0, -1,-1, 4,8, 5,11, 7,13, 9,14, 12,14,
    }),
    new HersheyChar(17, new int[]{
        14,11, 13,13, 10,14, 7,14, 4,13, 3,11, 4,9, 6,8, 11,7, 13,6, 14,4, 14,3, 13,1, 10,0, 7,0, 4,1, 3,3,
    }),
    new HersheyChar(12, new int[]{
        5,21, 5,4, 6,1, 8,0, 10,0, -1,-1, 2,14, 9,14,
    }),
    new HersheyChar(19, new int[]{
        4,14, 4,4, 5,1, 7,0, 10,0, 12,1, 15,4, -1,-1, 15,14, 15,0,
    }),
    new HersheyChar(16, new int[]{
        2,14, 8,0, -1,-1, 14,14, 8,0,
    }),
    new HersheyChar(22, new int[]{
        3,14, 7,0, -1,-1, 11,14, 7,0, -1,-1, 11,14, 15,0, -1,-1, 19,14, 15,0,
    }),
    new HersheyChar(17, new int[]{
        3,14, 14,0, -1,-1, 14,14, 3,0,
    }),
    new HersheyChar(16, new int[]{
        2,14, 8,0, -1,-1, 14,14, 8,0, 6,-4, 4,-6, 2,-7, 1,-7,
    }),
    new HersheyChar(17, new int[]{
        14,14, 3,0, -1,-1, 3,14, 14,14, -1,-1, 3,0, 14,0,
    }),
    new HersheyChar(14, new int[]{
        9,25, 7,24, 6,23, 5,21, 5,19, 6,17, 7,16, 8,14, 8,12, 6,10, -1,-1, 7,24, 6,22, 6,20, 7,18, 8,17, 9,15, 9,13, 8,11, 4,9, 8,7, 9,5, 9,3, 8,1, 7,0, 6,-2, 6,-4, 7,-6, -1,-1, 6,8, 8,6, 8,4, 7,2, 6,1, 5,-1, 5,-3, 6,-5, 7,-6, 9,-7,
    }),
    new HersheyChar(8, new int[]{
        4,25, 4,-7,
    }),
    new HersheyChar(14, new int[]{
        5,25, 7,24, 8,23, 9,21, 9,19, 8,17, 7,16, 6,14, 6,12, 8,10, -1,-1, 7,24, 8,22, 8,20, 7,18, 6,17, 5,15, 5,13, 6,11, 10,9, 6,7, 5,5, 5,3, 6,1, 7,0, 8,-2, 8,-4, 7,-6, -1,-1, 8,8, 6,6, 6,4, 7,2, 8,1, 9,-1, 9,-3, 8,-5, 7,-6, 5,-7,
    }),
    new HersheyChar(24, new int[]{
        3,6, 3,8, 4,11, 6,12, 8,12, 10,11, 14,8, 16,7, 18,7, 20,8, 21,10, -1,-1, 3,8, 4,10, 6,11, 8,11, 10,10, 14,7, 16,6, 18,6, 20,7, 21,10, 21,12,
    }),
};
