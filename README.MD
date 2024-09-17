# OBS - Zoom and Follow Mouse EG

## Description

This OBS Studio script creates a zoom effect and follows mouse movement on a selected video source. It's useful for highlighting specific parts of the screen during recordings or live streams.

## Features

- Dynamic zoom on a video source
- Follows mouse movement
- Cross-platform support (Windows, Linux, macOS)
- Customizable settings
- Activation via hotkeys

## Requirements

- OBS Studio (version 27.0.0 or higher)
- Lua 5.1 or higher

## Installation

1. Download the `obs-zoom-and-follow-mouse-eg.lua` file
2. In OBS Studio, go to Tools > Scripts
3. Click the "+" button and select the downloaded file
4. Configure the script settings according to your preferences

## Configuration

The script offers several configuration options:

- Zoom Source: Select the video source to apply the zoom effect
- Zoom Window Width: Width of the zoom window
- Zoom Window Height: Height of the zoom window
- Active Border: Size of the active border for movement
- Max Scroll Speed: Maximum scrolling speed
- Smooth Factor: Movement smoothing factor
- Zoom Duration: Duration of the zoom animation (in milliseconds)
- Enable Manual Offset: Enable/disable manual offset
- Manual X Offset: Manual offset on the X-axis
- Manual Y Offset: Manual offset on the Y-axis
- Enable debug logging: Enable/disable debug logging

## Usage

1. Configure the script in OBS Studio settings
2. Set up hotkeys to toggle zoom and follow
3. During recording or live streaming, use the hotkeys to control the zoom effect

## Main Functions

- Dynamic zoom on the selected source
- Follows mouse movement with customizable smoothing
- Automatic handling of scene changes and source removal
- Support for manual mouse offset

## Troubleshooting

If you encounter issues with the script, try:

1. Verifying that the selected source is valid and active
2. Restarting OBS Studio
3. Checking OBS logs for any error messages
4. Enabling debug logging in the script settings for more information

## Support

To report bugs or request new features, open an issue on GitHub or contact the script author.

## License

This script is released under the GNU General Public License v3.0. See the LICENSE file for more details.

## Version

Current version: 0.1.0

## Author

Edoardo Guzzi

## Acknowledgements

Special thanks to the OBS Studio community for their support and feedback.

## Inspiration

This script is inspired by the [tryptech/obs-zoom-and-follow](https://github.com/tryptech/obs-zoom-and-follow) repository. We appreciate their work and contribution to the OBS community.
