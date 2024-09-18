# OBS - Zoom and Follow Mouse EG

## Description

This script for OBS Studio creates a dynamic zoom effect and follows mouse movement on a selected video source. It is particularly useful for highlighting specific parts of the screen during recordings or live streaming, with support for multi-monitor setups.

## Features

- Dynamic zoom on any valid video source
- Smooth mouse-follow movement
- Cross-platform support (Windows, Linux, macOS)
- Multi-monitor support
- Customizable zoom and tracking speeds
- Activation via hotkeys
- Automatic scene switching management
- Smooth transitions during scene changes
- Debug mode for troubleshooting

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

- Zoom Value: Sets the maximum zoom level (from 1.1 to 5.0)
- Zoom Speed: Adjusts the speed of the zoom effect (from 0.01 to 1.0)
- Tracking Speed: Adjusts the speed of the tracking effect (from 0.01 to 1.0)
- Debug Mode: Enables/disables debug messages for troubleshooting

## Usage

1. Configure the script in OBS Studio settings
2. Set hotkeys to enable/disable zoom and tracking
3. During recording or live streaming, use the hotkeys to control the zoom and tracking effects

## Main Functions

- Dynamic zoom on the selected source with smooth animation
- Mouse movement tracking with customizable smoothing
- Automatic scene switching management and source removal
- Multi-monitor configuration support
- Smooth transitions during scene changes while in zoom mode
- Debug mode for easier troubleshooting

## Troubleshooting

If you encounter issues with the script, try:

1. Ensuring there is a valid video source in the current scene
2. Restarting OBS Studio
3. Checking the OBS logs for any error messages
4. Ensuring your version of OBS Studio is compatible
5. Enabling debug mode in the script settings for more information

## Support

To report bugs or request new features, open an issue on GitHub or contact the script's author.

## License

This script is released under the GNU General Public License v3.0. See the LICENSE file for more details.

## Version

Current version: 1.1

## Author

Edoardo Guzzi

## Acknowledgments

A special thanks to the OBS Studio community for their support and feedback.

## Inspiration

This script is inspired by various zoom and follow scripts in the OBS community, with additional features and improvements for multi-monitor support and smooth transitions.
