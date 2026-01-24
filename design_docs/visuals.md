The interface is presented using very old-school-looking terminal ASCII graphics.

The 3D perspective view of the world is very low res, and each pixel is mapped to an ASCII char. The view starts out as black and white, but can be upgraded to grayscale and then color, which helps with mineral and threat identification.

## Shading

Everything in the world, including the in-pod HUD, renders to a small-resolution framebuffer in a special paletted format.

There are two textures in the framebuffer:

1. The "foreground" : an ASCII char.
2. The "background" : a blank space behind each foreground.

A bloom effect is later applied based on data in the framebuffer.

### Foreground

The foreground pixel format contains the following values:

* Integer "color" representing a paletted color
* Integer "shape" representing a paletted ASCII char category.
* Float "density" representing the space occupancy of the ASCII char.
  * A density of 0 always maps to the space character, while larger values can map to different ASCII chars following the chosen "shape".
* Bool "transparent" representing whether a nearby surface underneath this one has the ability to bleed through (more info below).
* Float "shine" representing the HDR brightness of the char, which is only used for a Bloom effect.

Color and Shape will be packed into one 8-bit channel, as neither will get close to 255 different values.
Let's say 4 bits for each (currently I have 6 different shapes).
Density will be a hand-normalized float, using 7 bits of a UInt8 channel for itself.
The last bit after Density will be used for Transparency.
Shine will get its own 8-bit channel, very roughly mapping 255 values to the \[0, +Inf) range.

The texture format for these values will therefore be RGB_UInt_8.

The foreground data is rendered using opaque blending -- only the front-most face gets to control the output.
Note that under this arrangement, the Bloom effect only applies to the character glyph and not its background.

### Background

The background pixel format contains the following values:

* "color", using the same paletted color set as the foreground
* "density", similar to the density value in the foreground but here is used to dim the paletted color.
  * This means the background color is effectively 16-bit, while the foreground color is only 8-bit.
  * In other words, the background color has more variety (particularly in lightness) to offset the lack of character detail.

Unlike the foreground, the background has a pseudo-transparent effect: if a surface is marked as "transparent" and has the same depth as the foreground fragment, then it is discarded, allowing the next-closest surface behind it to write background values. This next-closest surface is referred to as the "partially-occluded" surface.

The background color written by a partially-occluded surface will use that surface's *foreground* color/density if the surface is itself opaque, or its usual background color/density if transparent.
This is a wholly-artistic choice which may change in the future.
The idea is that transparent surfaces are less about fine details and more about broad color?

To match the foreground color palette, density will be 7-bits, hand-normalized.
Color will use the same number of bits as foreground (currently 4).
So in total the background needs 11 bits of packed unsigned data, and we will use a R_UInt_16 format.

### Shader output

The "surface properties" output by a shader in this game, and later packed into the above framebuffer output depending on pass, are as follows:

* Foreground Color, as a uint (not to go above a certain low value).
* Foreground Shape, as a uint (not to go above a certain low value).
* Foreground Density, as a float from 0 to 1
* Foreground Transparency, as a bool
* Foreground Shine, as a float
* Background Color, as a uint (not to go above a certain low value).
* Background Density, as a float from 0 to 1

### Render passes

Keep in mind that resolution is purposefully low (and constant), so fragment performance is likely a non-issue.

1. Pick a low resolution for rendering the world. It doesn't have to be square, but we might prefer it that way so that FOV is fixed and it's easier to make the in-pod HUD work right.
2. Draw foreground, doing depth writes/tests with a depth texture.
3. Draw background, doing depth writes/tests with a different depth *buffer* (doesn't need to be a sampleable texture), while reading the foreground depth texture to support the pseudo-transparency effect described above.
4. Take the window resolution rounded down to the nearest multiple of the foreground/background resolution. To prevent stretching, take the side with a larger multiple and recalculate resolution to use the smaller multiple.
5. Clear the screen to a particular background color (corrected aspect ratio will leave blank areas).
6. Draw a quad of the screen size calculated in 4, sampling from the foreground/background to determine char and color, then from the rendered ASCII chars.
7. Along with the rendered ASCII chars, output a second color buffer which contains the colored foreground "shine".
8. Apply multiple blur passes to the Shine color buffer (kernel to be determined aesthetically).
9. Add the blurred Shine passes back to the original render to get the blurred image.
10. Add a final pseudo-CRT overlay effect.

In debug builds, the game is displayed within a Dear ImGUI window
  alongside useful information and debug settings.

### Lighting

Lights are direct-lighting only (finer detail, for such a low-fidelity renderer, would be at best useless and at worst confusing). Each light has a shadowmap, using a custom format containing the following values:

1. Distance from the light to the nearest transparent occluder.
2. Density of that first transparent occluder.
3. Distance at which the incoming light is 0 either due to many transparent occluders or a single opaque one.

This allows for partial light attenuation due to a single layer of transparent material such as smoke, followed by a total attenuation further away.
Intermediary attenuation can be calculated for distances in-between these thresholds.

In this renderer, we can probably get away with pretty low-res shadow-maps.

I'm not sure yet of the right way to apply light/shadows.

### Rocks

Rock is colored based on the proportions of minerals it contains.
A global 3D noise is used to lerp between the different mineral indices,
  and then the rock surface blends between that mineral and a "plain rock" look
  based on how much of the mineral is present.

Minerals primarily differ by their hue, foreground shape, and foreground/background density.

Each mineral's color has a distinct hue, mildly-varying lightness, and similar saturation.
Each mineral also has its own choice of foreground shape.

### FX

* We could create an interesting distortion effect by switching the char atlas lookup texture
(which maps a Shape/Density pair to the UV rect for the corresponding char) to use linear instead of clamp sampling.
This might be useful for damage or mysterious environmental objects.
* Smoke would look very cool, we should think about how to implement it
(many small billboards? Handful of large billboards with fragment discarding? Volumetric cube?)

## Assets needed

First, we need a font texture ("font-map"), containing all chars.
The simplest option is to load a real font on startup and generate the font-map.

Next, we need some way to convert a shape+density value to a particular character in the font-map.
We will define a data specification mapping shape+density values to chars,
    and generate a texture mapping shape+density (represented as pixel Y and X respectively)
    directly to a font-map UV rectangle.
Note that different shape+density values are allowed to map to the same char;
    an important use for this is outlined in the [section below](#direct-rendering-of-chars).

Finally, we need a color palette.
This is simply a Nx1 texture, mapping color index to RGB.

## Direct rendering of chars

Because the user-interface is rendered like the 3D world,
    we definitely want an easier way for some 3D surfaces to output characters directly.
This will be accomplished with special shape types that cover the whole range of ASCII chars:
    "lowercase letters", "uppercase letters", "digits", "punctuation".
As noted above, it's OK for the same char to appear in two different shape types,
    so these new shapes will not affect the existing ones.

GLSL doesn't support string/char literals, so we'll add some GLSL and Julia convenience functions
    to convert a char to a shape+density value.
Perhaps a small UBO can directly map ascii codes to shape+density,
    however this wouldn't scale to UTF-8 chars.

## Screen Segmentation

The border between the inside of the pod (i.e. the UI) and the rest of the world is the "screen segmentation".
It will be drawn as a thick line *in-between* character grid cells,
    making it the only diagetic rendered object that isn't done through the character system.

The segmentation will be composed of straight lines and rounded 90-degree corners.
Rendering is therefore done in two batches:
1. All straight-lines, each defined as:
   1. A starting corner of the character grid, represented as the cell immediately after that corner.
   2. An ending corner of the character grid, represented in the same way.
2. All corner lines, each defined as:
   1.  The cell of the chracter grid that they cross through (being rounded corners, they don't stay perfectly between cells)
   2.  Which corner they sit on (e.x. {0, 0} for minXY; {1, 1} for maxXY)