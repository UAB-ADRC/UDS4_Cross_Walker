# JSON Script for Data Processing
## 1. Json_script.py
This Python script processes Excel files in a given folder, extracts relevant data, and saves the output as JSON. It's designed to help automate the conversion of data elements between UDS3 and UDS4 formats.

### Requirements

Before you run the script, make sure you have Python installed on your system along with the required libraries. To install the necessary dependencies, follow these steps:

1. Install Python (if not already installed):
   - Download Python: https://www.python.org/downloads/
   - Ensure that Python and `pip` (Python's package installer) are added to your system's PATH.

2. Install required libraries by running:
   ```bash
   pip install -r requirements.txt
    ```

### How to Use the Script
Step 1: Prepare Your Files
Ensure that your Excel files are located in a folder on your computer. These files should have multiple sheets containing data in a specific structure.

Step 2: Run the Script
To run the script, open a terminal (or command prompt) and navigate to the folder where the script is located. Then, run the following command, replacing <folder_path> with the path to the folder containing your Excel files:
 ```bash
python Json_script.py <folder_path>
 ```
For example:
 ```bash
python Json_script.py C:/Users/YourUsername/Downloads/crosswalks
 ```

## Troubleshooting
If you encounter any issues, ensure that you are using the correct Python version and have installed all dependencies from the requirements.txt file.
Make sure that the folder path provided contains only .xlsx files that match the required format.
