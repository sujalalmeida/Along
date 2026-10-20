# Checking performance

Use an optimized build with Accessibility enabled. Model tests do not measure the time other apps take to respond to window operations.

Record your Mac, macOS version, Along version, refresh rate, Reduce Motion setting, and the names/count of managed apps and windows.

1. Measure idle CPU and memory after closing setup and the menu panel.
2. Start a row and repeat the same sequence of navigation and scrolling actions with the same windows. Record CPU and memory during that sequence.
3. Open and close the menu panel and a test window repeatedly. Stop the row, wait for the app to settle, and compare memory with the same starting state.
4. Check rapid direction changes, holding an arrow key, trackpad scrolling, and apps that respond slowly to Accessibility requests. Look for input backlog or a final jump after input stops.
5. Enable Reduce Motion and repeat navigation and restoration.

Compare equivalent states over repeated runs. A single RSS reading does not establish a memory improvement or a leak; SwiftUI and macOS may retain caches. Instruments can help distinguish retained window/view objects from cached memory.

The engine avoids full enumeration on each navigation input and releases obsolete references, but those design choices do not establish a specific latency or memory benchmark. Earlier development observations are preserved in [history](history/v0.4-v0.5-performance.md).
