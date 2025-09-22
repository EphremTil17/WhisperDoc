
import asyncio
import websockets
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def test_websocket():
    uri = "ws://localhost:9989/ws"
    try:
        async with websockets.connect(uri) as websocket:
            logger.info(f"Connected to {uri}")
            
            # Send a test message
            message = "Hello, WebSocket!"
            await websocket.send(message)
            logger.info(f"> {message}")
            
            # Receive the response
            response = await websocket.recv()
            logger.info(f"< {response}")
            
            # Verify the response
            if response == f"Message text was: {message}":
                logger.info("✅ WebSocket echo test passed!")
                return True
            else:
                logger.error(f"❌ WebSocket echo test failed! Received: {response}")
                return False
                
    except Exception as e:
        logger.error(f"❌ WebSocket connection failed: {e}")
        return False

if __name__ == "__main__":
    if asyncio.run(test_websocket()):
        # Exit with success code
        exit(0)
    else:
        # Exit with failure code
        exit(1)
