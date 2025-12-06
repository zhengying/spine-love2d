-- Basic usage example configuration
-- Run with: love examples/basic_usage/

function love.conf(t)
    t.window.title = "Spine Love2D Runtime - Basic Usage Example"
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = false
    t.window.vsync = true
    t.console = true -- Enable console for debugging
end