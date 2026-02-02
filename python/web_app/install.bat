@echo off
echo ============================================
echo IPD Control Panel - Installing Dependencies
echo ============================================
echo.

echo Installing Flask and WebSocket dependencies...
pip install -r requirements.txt

echo.
echo ============================================
echo Installation complete!
echo ============================================
echo.
echo You can now run: python app.py
echo Or double-click: start_control_panel.bat
echo.

pause
