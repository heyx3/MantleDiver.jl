The interface is presented using very old-school-looking terminal ASCII graphics.

The 3D perspective view of the world is very low res, and each pixel is mapped to an ASCII char. The view starts out as black and white, but can be upgraded to grayscale and then color, which helps with mineral and threat identification.

## Framebuffer

Everything in the world, including the in-pod HUD, renders to an integer framebuffer.
The framebuffer stores for each pixel, a "shade" representing a paletted color and a "density" representing a paletted ASCII char.
It also stores a background "density" and "shade" for each character in a separate output texture.
The background "density" does not map to an ASCII char like the foreground, but to a scale value for the background color.
This leads to many more background colors than foreground colors.

The foreground data is drawn opaquely, with only the front-most surface affecting it.
Background data is also drawn opaquely, but filtering out the front-most face with depth testing
    so that the *second-most-front* surface draws to it.

### Render passes

Keep in mind that resolution is purposefully low (and constant), so fragment performance is likely a non-issue.

1. Pick a low resolution for rendering the world. It doesn't have to be square, but we might prefer it that way so that FOV is fixed and it's easier to make the in-pod HUD work right.
2. Draw foreground using RG_8_Unorm, and write/test with depth buffer.
3. Draw background using RG_8_Unorm, and write/test with a *different* depth buffer, while discarding a pixel if it has the same depth as the first depth buffer.
4. Round the window resolution down to the nearest multiple of the foreground/background resolution, along each axis. Get a render target of this size.
5. Draw into the render target, sampling from the foreground/background and then sampling from textures for the ASCII char pixels and shade color.
6. Clear the screen to a particular background color, then draw the render target to it, shrinking to preserve its aspect ratio.

## Rocks

Rock is colored based on the proportions of minerals it contains.
The rock surface color is not an overall blend of mineral colors, but a noisy speckle of the colors,
    where each pixel picks one of its minerals with a weighted-random chance.

Each mineral's shade has a distinct hue, mildly-varying lightness, and similar saturation.