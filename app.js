// app.js - Motor monitoring dashboard driver

// Config
const MAX_DATA_POINTS = 30; // How many data points to show on the chart
const REFRESH_RATE_MS = 1000; // Update rate in milliseconds

// Helper function to initialize a line chart
function createChart(canvasId, yAxisTitle, labels, colors, yMin, yMax) {
    const ctx = document.getElementById(canvasId).getContext('2d');
    
    // Create an array indicating relative time samples e.g. -29, -28 ... 0
    const timeLabels = Array(MAX_DATA_POINTS).fill(0).map((_, i) => i - (MAX_DATA_POINTS - 1));

    const datasets = labels.map((label, index) => ({
        label: label,
        data: Array(MAX_DATA_POINTS).fill(null), // Empty initial data
        borderColor: colors[index],
        backgroundColor: 'transparent', // Scientific plots: no fill under curves
        borderWidth: 1.5, // Thin, precise lines
        tension: 0, // 0 for sharp, accurate points; no bezier smoothing
        pointRadius: 0, // Hide data dots unless hovered
        pointHoverRadius: 4
    }));

    return new Chart(ctx, {
        type: 'line',
        data: {
            labels: timeLabels,
            datasets: datasets
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation: {
                duration: 0 // Disable animation for immediate data mapping
            },
            interaction: {
                mode: 'index',
                intersect: false,
            },
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        color: '#111827', // Dark gray/black
                        font: {
                            family: 'ui-monospace, Consolas, monospace',
                            size: 11
                        },
                        boxWidth: 12
                    }
                }
            },
            scales: {
                x: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Samples (t)',
                        color: '#374151',
                        font: {
                            family: 'ui-monospace, Consolas, monospace',
                            size: 10
                        }
                    },
                    grid: {
                        color: '#e5e7eb', // Light gray standard grid
                        borderColor: '#9ca3af' // Border framing
                    },
                    ticks: {
                        color: '#374151',
                        font: {
                            family: 'ui-monospace, Consolas, monospace',
                            size: 10
                        },
                        maxRotation: 0,
                        autoSkip: true,
                        maxTicksLimit: 10
                    }
                },
                y: {
                    display: true,
                    title: {
                        display: true,
                        text: yAxisTitle,
                        color: '#374151',
                        font: {
                            family: 'ui-monospace, Consolas, monospace',
                            size: 10
                        }
                    },
                    grid: {
                        color: '#e5e7eb',
                        borderColor: '#9ca3af'
                    },
                    ticks: {
                        color: '#374151',
                        font: {
                            family: 'ui-monospace, Consolas, monospace',
                            size: 10
                        }
                    },
                    suggestedMin: yMin,
                    suggestedMax: yMax
                }
            }
        }
    });
}

// 1. Initialize Charts
// Temperatures: Red for Motor Temp
const tempChart = createChart('tempChart', 'Temperature (°C)', ['Motor Temp'], ['#ef4444'], 0, 80);

// Voltage: Blue for Terminal Voltage
const voltageChart = createChart('voltageChart', 'Voltage (V)', ['Terminal Voltage'], ['#2563eb'], 0, 250);

// Current: Orange for Single Phase Motor
const currentChart = createChart('currentChart', 'Current (A)', ['Main Phase'], ['#f97316'], 0, 5);

// Vibrations: Green, Purple, Orange (Converted to m/s²)
const vibrationChart = createChart('vibrationChart', 'Acceleration (m/s²)', ['X-Axis', 'Y-Axis', 'Z-Axis'], ['#10b981', '#8b5cf6', '#f97316'], -10, 10);

// Generic function removed - data is now normalized directly.

// 2. Helper to update chart data
function appendDataToChart(chart, newValuesArray) {
    chart.data.datasets.forEach((dataset, index) => {
        dataset.data.push(newValuesArray[index]);
        if (dataset.data.length > MAX_DATA_POINTS) {
            dataset.data.shift(); // Remove oldest data point
        }
    });
    chart.update();
}


// --- WEB SERIAL COMMUNICATION ---
let serialPort = null;
let serialReader = null;
let serialBuffer = '';
let connectionTime = 0;
let isDataDumped = false; // Flag to dump initial connection data

// Variables to hold mapped Arduino sensor data
let motorData = {
    temp: 0,
    voltage: 0,
    current: 0,
    x: 0, // Default resting point for normalized vibration
    y: 0,
    z: 0,
    relay: 0
};

let availablePorts = [];

// Populate the COM port dropdown with previously granted ports on load
window.addEventListener('load', async () => {
    try {
        const selector = document.getElementById('port-selector');
        const ports = await navigator.serial.getPorts();
        availablePorts = ports;

        // Add already authorized ports to dropdown
        ports.forEach((port, index) => {
            const option = document.createElement('option');
            option.value = index;
            // Web Serial API doesn't expose the exact "COM3" name for privacy reasons
            // But we can show it is an authorized device with its USB vendor ID
            const info = port.getInfo();
            option.text = `Authorized USB Device (VID: ${info.usbVendorId || 'Unknown'})`;
            selector.appendChild(option);
        });

        // Always provide an option to prompt for a new COM port connection
        const newOption = document.createElement('option');
        newOption.value = 'new';
        newOption.text = '+ Add New COM Port...';
        selector.appendChild(newOption);

    } catch (err) {
        console.error("Failed to list ports:", err);
    }
});

document.getElementById('connect-serial').addEventListener('click', async () => {
    try {
        const selector = document.getElementById('port-selector');
        const selectedValue = selector.value;
        let selectedPort = null;

        if (selectedValue === 'new') {
            // Prompt the browser's native COM port selection pop-up
            selectedPort = await navigator.serial.requestPort();
            // Automatically add this new port to our dropdown list for next time
            availablePorts.push(selectedPort);
            const newIndex = availablePorts.length - 1;
            const option = document.createElement('option');
            option.value = newIndex;
            option.text = `Newly Authorized USB Device`;
            selector.insertBefore(option, selector.lastChild); // Insert before the '+ Add New' option
            selector.value = newIndex; // Auto-select it
        } else if (selectedValue !== "") {
            // Use an already authorized port
            selectedPort = availablePorts[selectedValue];
        }

        if (selectedPort) {
            connectToPort(selectedPort);
        } else {
            alert('Please select a port from the dropdown first.');
        }
    } catch (err) {
        console.error('There was an error selecting the serial port:', err);
    }
});

async function connectToPort(port) {
    try {
        serialPort = port;
        // Open port at 115200 baud matching Arduino code
        await serialPort.open({ baudRate: 115200 });
        
        connectionTime = Date.now();
        isDataDumped = false; // Reset the dump flag for the new connection
        
        document.getElementById('connect-serial').innerText = "Connected";
        document.getElementById('connect-serial').classList.replace('bg-blue-500', 'bg-green-500');

        const decoder = new TextDecoderStream();
        serialPort.readable.pipeTo(decoder.writable);
        serialReader = decoder.readable.getReader();

        // Start reading loop
        readSerialLoop();
    } catch (err) {
        console.error("Error opening port", err);
    }
}

async function readSerialLoop() {
    while (true) {
        const { value, done } = await serialReader.read();
        
        if (value) {
            serialBuffer += value;
            // Split by newline since Arduino uses Serial.println
            let lines = serialBuffer.split('\n');
            
            // The last string is usually incomplete, keep it in the buffer
            serialBuffer = lines.pop(); 

            for (let line of lines) {
                line = line.trim();
                if (line.startsWith('{') && line.endsWith('}')) {
                    try {
                        const parsedData = JSON.parse(line);
                        
                        // Handle Temperature - receive pre-calculated directly
                        if (parsedData.tempC !== undefined) {
                            motorData.temp = parsedData.tempC;
                        }

                        if (parsedData.x !== undefined) motorData.x = parsedData.x;
                        if (parsedData.y !== undefined) motorData.y = parsedData.y;
                        if (parsedData.z !== undefined) motorData.z = parsedData.z;
                        if (parsedData.voltage !== undefined) motorData.voltage = parsedData.voltage;
                        if (parsedData.current !== undefined) motorData.current = parsedData.current;
                        if (parsedData.relay !== undefined) motorData.relay = parsedData.relay;
                        
                    } catch (e) {
                        console.warn("JSON parse error from Serial data:", e);
                    }
                }
            }
        }
        
        if (done) {
            serialReader.releaseLock();
            break;
        }
    }
}

let lastConstantCurrent = -1;
let currentConstantSince = 0;
let lastValidVoltage = 0;
let consecutiveVoltageZeros = 0;

// 3. Data Simulation & Update Loop
setInterval(() => {
    // Load the latest variables from Arduino 
    const t_motor = motorData.temp;
    let v_term = motorData.voltage || 0;
    
    // Outlier rejection for sudden voltage drops to zero
    if (v_term === 0 && lastValidVoltage > 20) {
        consecutiveVoltageZeros++;
        if (consecutiveVoltageZeros < 3) {
            v_term = lastValidVoltage; // Ignore up to 2 sudden zero readings
        } else {
            lastValidVoltage = 0; // A real drop
        }
    } else {
        consecutiveVoltageZeros = 0;
        lastValidVoltage = v_term;
    }

    const vib_x = motorData.x;
    const vib_y = motorData.y;
    const vib_z = motorData.z;

    // Retrieve voltage, current, and relay state natively from Arduino string
    const i_main = motorData.current || 0;
    const relay_state = motorData.relay || 0;

    // Normalized vibration data directly as integers
    const ms2_x = Math.round(vib_x);
    const ms2_y = Math.round(vib_y);
    const ms2_z = Math.round(vib_z);

    // After 2 seconds of connection, dump the initial noisy data once before calculating RMS
    if (serialPort && !isDataDumped && (Date.now() - connectionTime > 2000)) {
        vibrationChart.data.datasets.forEach(dataset => dataset.data.fill(null));
        isDataDumped = true;
    }

    // Push real Arduino data to other charts regardless
    appendDataToChart(tempChart, [t_motor]);
    appendDataToChart(voltageChart, [v_term]);
    appendDataToChart(currentChart, [i_main]);

    // Check if the accelerometer is uncalibrated (values pushing past +-50 bounds)
    const isVibNotCalibrated = (Math.abs(ms2_x) > 50 || Math.abs(ms2_y) > 50 || Math.abs(ms2_z) > 50);

    // Only push vibration data to the chart/history if it IS calibrated 
    // so we don't poison the RMS calculation arrays.
    if (!isVibNotCalibrated) {
        appendDataToChart(vibrationChart, [ms2_x, ms2_y, ms2_z]);
    } else {
        // Option to just tick time forward without breaking RMS magnitude
        appendDataToChart(vibrationChart, [null, null, null]);
    }

    // --- CALCULATE ANALYTICS ---
    // Calculate AC variation (RMS) of recent 3D vibrations to remove static gravity offset
    const xDataset = vibrationChart.data.datasets[0].data.filter(val => val !== null);
    const yDataset = vibrationChart.data.datasets[1].data.filter(val => val !== null);
    const zDataset = vibrationChart.data.datasets[2].data.filter(val => val !== null);
    
    let effective_x = 0;
    let effective_y = 0;
    let effective_z = 0;
    let effective_vib = 0; // Total 3D variation

    // Calculate RMS only after 2 seconds dump time has passed
    const hasEnoughDataTime = serialPort && isDataDumped;

    if (hasEnoughDataTime && xDataset.length > 0 && yDataset.length > 0 && zDataset.length > 0) {
        // 1. Find the mean (DC component) for each axis
        const meanX = xDataset.reduce((a, b) => a + b, 0) / xDataset.length;
        const meanY = yDataset.reduce((a, b) => a + b, 0) / yDataset.length;
        const meanZ = zDataset.reduce((a, b) => a + b, 0) / zDataset.length;
        
        // 2. Find variance of the AC component for each axis
        const varianceX = xDataset.reduce((a, b) => a + Math.pow(b - meanX, 2), 0) / xDataset.length;
        const varianceY = yDataset.reduce((a, b) => a + Math.pow(b - meanY, 2), 0) / yDataset.length;
        const varianceZ = zDataset.reduce((a, b) => a + Math.pow(b - meanZ, 2), 0) / zDataset.length;
        
        // 3. Obtain individual RMS values
        effective_x = Math.sqrt(varianceX);
        effective_y = Math.sqrt(varianceY);
        effective_z = Math.sqrt(varianceZ);
        
        // 4. Total RMS is the square root of the sum of variances (Total 3D dynamic magnitude)
        effective_vib = Math.sqrt(varianceX + varianceY + varianceZ);
    }

    if (i_main >= 3.2 && i_main === lastConstantCurrent) {
        currentConstantSince += REFRESH_RATE_MS;
    } else {
        lastConstantCurrent = i_main;
        currentConstantSince = 0;
    }

    // Update UI Motor Status relying on main phase current
    const devStatusEl = document.getElementById('stat-device-status');
    if (serialPort && serialPort.readable) {
        if (currentConstantSince >= 10000) {
            devStatusEl.innerHTML = '<span class="inline-block px-3 py-1 bg-red-600 text-white rounded-full text-sm font-bold shadow uppercase tracking-wide">Motor Power: TRIPPED</span>';
            devStatusEl.className = 'mt-2';
        } else if (i_main >= 0.05) {
            devStatusEl.innerHTML = '<span class="inline-block px-3 py-1 bg-green-500 text-white rounded-full text-sm font-bold shadow uppercase tracking-wide">Motor Power: ON</span>';
            devStatusEl.className = 'mt-2';
        } else {
            devStatusEl.innerHTML = '<span class="inline-block px-3 py-1 bg-red-500 text-white rounded-full text-sm font-bold shadow uppercase tracking-wide">Motor Power: OFF</span>';
            devStatusEl.className = 'mt-2';
        }
    } else {
        devStatusEl.innerText = 'OFFLINE';
        devStatusEl.className = 'text-xl font-bold text-gray-400 mt-1 uppercase tracking-wide';
    }

    // Calculate Main Current State limit
    const currentEl = document.getElementById('stat-peak-current');
    if (i_main > 0) {
        currentEl.innerText = `${i_main.toFixed(2)} A`;
        currentEl.className = 'text-xl font-bold text-orange-600 mt-1';
    } else {
        currentEl.innerText = '0.00 A';
        currentEl.className = 'text-xl font-bold text-gray-400 mt-1';
    }

    // Terminal Voltage State
    const voltageEl = document.getElementById('stat-voltage');
    if (v_term > 0) {
        voltageEl.innerText = `${v_term.toFixed(2)} V`;
        voltageEl.className = 'text-xl font-bold text-blue-600 mt-1';
    } else {
        voltageEl.innerText = '0.00 V';
        voltageEl.className = 'text-xl font-bold text-gray-400 mt-1';
    }

    // Show converted values in dashboard as standard RMS m/s² (No Not Calibrated text overrides here)
    document.getElementById('stat-vib-x').innerText = effective_x.toFixed(2) + ' m/s²';
    document.getElementById('stat-vib-x').className = 'text-xl font-bold text-gray-700 mt-1';
    document.getElementById('stat-vib-y').innerText = effective_y.toFixed(2) + ' m/s²';
    document.getElementById('stat-vib-y').className = 'text-xl font-bold text-gray-700 mt-1';
    document.getElementById('stat-vib-z').innerText = effective_z.toFixed(2) + ' m/s²';
    document.getElementById('stat-vib-z').className = 'text-xl font-bold text-gray-700 mt-1';
    
    document.getElementById('stat-temp').innerText = Math.round(t_motor) + ' °C';

    // --- STATE MACHINE & ALERTS ---
    const alertBox = document.getElementById('alert-box');
    const latestEvent = document.getElementById('latest-event');
    
    // Simple thresholds using available data (Updated for RMS AC variation)
    let isWarning = false;
    let isCritical = false;
    let alertMsg = (serialPort && serialPort.readable) 
        ? 'System operating nominally. Receiving Data...' 
        : 'System offline. Awaiting connection...';

    if (serialPort && serialPort.readable && isVibNotCalibrated) {
        isWarning = true;
        alertMsg = 'WARNING: That accelarometr not calibrated.';
    } else if (i_main > 3.5) {
        isCritical = true;
        alertMsg = 'CRITICAL: Overcurrent (>3.5A)! Motor tripped.';
    } else if (effective_vib > 4.0) { // Critical RMS vibration limit
        isCritical = true;
        alertMsg = 'CRITICAL: Safety thresholds exceeded! Motor trip advised.';
    } else if (i_main >= 3.2 && i_main <= 3.5) {
        isWarning = true;
        alertMsg = 'WARNING: Rated current exceeded (between 3.2A and 3.5A).';
    } else if (Math.abs(vib_z) > 2.5) { // Axial (Z) Peak Vibration limit
        isWarning = true;
        alertMsg = 'WARNING: Peak axial vibration exceeds 2.5 m/s².';
    } else if (effective_vib > 2.0) { // Warning RMS vibration limit
        isWarning = true;
        alertMsg = 'WARNING: RMS Vibration levels are high. Inspect motor.';
    }

    if (isCritical) {
        alertBox.className = 'p-4 bg-red-50 text-red-800 rounded border border-red-200 transition-colors duration-300';
    } else if (isWarning) {
        alertBox.className = 'p-4 bg-yellow-50 text-yellow-800 rounded border border-yellow-200 transition-colors duration-300';
    } else {
        alertBox.className = 'p-4 bg-green-50 text-green-800 rounded border border-green-200 transition-colors duration-300';
    }

    latestEvent.innerText = alertMsg;

}, REFRESH_RATE_MS);

// Manual Switch Logic
document.getElementById('manual-off-btn').addEventListener('click', async () => {
    if (serialPort && serialPort.writable) {
        // Send a kill command to the Arduino / Node over TX. 
        // e.g. You might want to format this according to what your firmware expects.
        try {
            const encoder = new TextEncoder();
            const writer = serialPort.writable.getWriter();
            await writer.write(encoder.encode('{"command": "OFF"}\n'));
            writer.releaseLock();
            
            // Visual feedback
            const btn = document.getElementById('manual-off-btn');
            btn.innerText = 'Sent...';
            setTimeout(() => { btn.innerText = 'Turn Off'; }, 1000);
            
            console.log("Manual OFF command sent to hardware.");
        } catch (err) {
            console.error("Failed to send OFF command", err);
        }
    } else {
        alert("Connect to the device before attempting to turn it off.");
    }
});