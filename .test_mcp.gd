extends EditorScript

func _run() -> void:
    # Try to instantiate the MCP client
    var client = preload("res://addons/godot_mcp/mcp_client.gd").new()
    print("MCPClient created: ", client != null)
    print("Class: ", client.get_class())
    print("Script: ", client.get_script())
    
    # Try connecting
    client.connect_to_server()
    print("connect_to_server() called")
    
    # Wait a bit
    await get_tree().create_timer(5.0).timeout
    print("After 5s timeout, is_connected: ", client.is_connected_to_server())
    
    # Check status
    var status = client.get_godot_status()
    print("Status: ", status)
