import React, { useState, useEffect } from 'react';
import { AlertCircle, X } from 'lucide-react';

interface Alert {
    id: number;
    node_id: string;
    message: string;
    timestamp: string;
    read: boolean;
}

interface AlertPopupProps {
    token: string;
    gatewayUrl: string;
}

const AlertPopup: React.FC<AlertPopupProps> = ({ token, gatewayUrl }) => {
    const [alerts, setAlerts] = useState<Alert[]>([]);
    const [visible, setVisible] = useState(false);

    useEffect(() => {
        if (!token) return;

        const fetchAlerts = async () => {
            try {
                const res = await fetch(`${gatewayUrl}/api/system/alerts`, {
                    headers: { 'Authorization': `Bearer ${token}` }
                });
                if (res.ok) {
                    const data = await res.json();
                    // Just show the latest one if any
                    if (data.length > 0) {
                        setAlerts(data);
                        setVisible(true);
                    }
                }
            } catch (e) {
                console.error("Failed to fetch alerts", e);
            }
        };

        // Poll every 5 seconds
        const interval = setInterval(fetchAlerts, 5000);
        fetchAlerts(); // Initial fetch

        return () => clearInterval(interval);
    }, [token, gatewayUrl]);

    if (!visible || alerts.length === 0) return null;

    const latestAlert = alerts[0]; // Assuming sorted DESC

    return (
        <div style={{
            position: 'fixed',
            bottom: '20px',
            right: '20px',
            backgroundColor: '#ef4444', // Red-500
            color: 'white',
            padding: '16px',
            borderRadius: '8px',
            boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1)',
            zIndex: 1000,
            display: 'flex',
            alignItems: 'start',
            gap: '12px',
            maxWidth: '400px',
            animation: 'slideIn 0.3s ease-out'
        }}>
            <AlertCircle size={24} />
            <div>
                <h4 style={{ margin: '0 0 4px 0', fontWeight: 'bold' }}>Alert Detected!</h4>
                <p style={{ margin: 0, fontSize: '14px' }}>{latestAlert.message}</p>
                <span style={{ fontSize: '12px', opacity: 0.8 }}>{new Date(latestAlert.timestamp).toLocaleTimeString()}</span>
            </div>
            <button
                onClick={() => setVisible(false)}
                style={{
                    background: 'none',
                    border: 'none',
                    color: 'white',
                    cursor: 'pointer',
                    padding: '0'
                }}
            >
                <X size={20} />
            </button>
        </div>
    );
};

export default AlertPopup;
