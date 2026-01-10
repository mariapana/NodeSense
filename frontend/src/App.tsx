
import React, { useEffect, useState } from 'react';
import { Activity, Server, Plus, ShieldCheck, RefreshCw, Smartphone, Trash2, Network, FileText, X } from 'lucide-react';
import AlertPopup from './AlertPopup';

const GATEWAY_URL = ''; // Relative path, handled by Vite Proxy

interface NodeData {
    id: string;
    name: string;
    last_seen: string;
}

interface ServiceData {
    id: string;
    name: string;
    replicas: number;
    image: string;
}

function App() {
    const [view, setView] = useState<'dashboard' | 'system'>('dashboard');
    const [nodes, setNodes] = useState<NodeData[]>([]);
    const [token, setToken] = useState<string | null>(null);
    const [isAdmin, setIsAdmin] = useState(false);

    // System View State
    const [services, setServices] = useState<ServiceData[]>([]);
    const [selectedService, setSelectedService] = useState<string | null>(null);
    const [logs, setLogs] = useState<string[]>([]);
    const [loadingLogs, setLoadingLogs] = useState(false);

    // Fetch Nodes
    const fetchNodes = async () => {
        try {
            const res = await fetch(`${GATEWAY_URL}/api/nodes`);
            if (!res.ok) return;
            const data = await res.json();
            if (Array.isArray(data)) setNodes(data);
        } catch (err) { console.error(err); }
    };

    // Fetch System Topology
    const fetchTopology = async () => {
        if (!token || !isAdmin) return;
        try {
            const res = await fetch(`${GATEWAY_URL}/api/system/topology`, {
                headers: { 'Authorization': `Bearer ${token}` }
            });
            if (res.ok) {
                const data = await res.json();
                setServices(data);
            }
        } catch (e) { console.error(e); }
    }

    // Fetch Logs
    const fetchLogs = async (serviceName: string) => {
        setLoadingLogs(true);
        setSelectedService(serviceName);
        setLogs([]);
        try {
            const res = await fetch(`${GATEWAY_URL}/api/system/logs/${serviceName}`, {
                headers: { 'Authorization': `Bearer ${token}` }
            });
            if (res.ok) {
                const data = await res.json();
                setLogs(data.logs || []);
            } else {
                setLogs([`Failed to fetch logs: ${res.status} ${res.statusText} (Service: ${serviceName})`]);
            }
        } catch (e) {
            setLogs(["Error connecting to log endpoint."]);
        }
        setLoadingLogs(false);
    }

    useEffect(() => {
        fetchNodes();
        const interval = setInterval(fetchNodes, 5000);
        return () => clearInterval(interval);
    }, []);

    useEffect(() => {
        if (view === 'system' && isAdmin) {
            fetchTopology();
        }
    }, [view, isAdmin]);

    // Helper: Parse JWT (Simple implementation)
    const parseJwt = (token: string) => {
        try {
            const base64Url = token.split('.')[1];
            const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
            const jsonPayload = decodeURIComponent(window.atob(base64).split('').map(function (c) {
                return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
            }).join(''));
            return JSON.parse(jsonPayload);
        } catch (e) {
            return null;
        }
    };

    // Simulator
    const simulateNode = async () => {
        if (!token) {
            alert("Please Authenticate first (Click 'Get Token').");
            return;
        }

        const id = `sim-node-${Math.floor(Math.random() * 1000)}`;
        const memTotal = 16 * 1024 * 1024 * 1024; // 16GB
        const memUsed = Math.random() * memTotal * 0.8;

        const payload = {
            node_id: id,
            timestamp: new Date().toISOString(),
            metrics: [
                { name: 'cpu_usage', value: Math.random() * 100, unit: '%' },
                { name: 'mem_used', value: memUsed, unit: 'bytes' },
                { name: 'mem_total', value: memTotal, unit: 'bytes' },
                { name: 'disk_percent', value: Math.random() * 90, unit: '%' },
                { name: 'process_count', value: Math.floor(Math.random() * 200) + 50, unit: 'count' },
                { name: 'net_bytes_recv', value: Math.random() * 1000000, unit: 'bytes' },
                { name: 'net_bytes_sent', value: Math.random() * 500000, unit: 'bytes' }
            ]
        };

        try {
            await fetch(`${GATEWAY_URL}/ingest`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify(payload)
            });
            fetchNodes();
        } catch (e) {
            console.error(e);
            alert("Ingest failed");
        }
    };

    const getToken = async () => {
        const username = prompt("Enter Username (admin/viewer):", "");
        if (!username) return;
        const password = prompt("Enter Password:", "");
        if (!password) return;

        const secret = prompt("Please enter Client Secret (default: secret):", "");
        if (secret === null) return;

        try {
            const res = await fetch(`${GATEWAY_URL}/api/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    username: username,
                    password: password,
                    client_secret: secret
                })
            });
            const data = await res.json();
            if (data.access_token) {
                setToken(data.access_token);
                // Decode token to check role
                const decoded = parseJwt(data.access_token);
                const roles = decoded?.realm_access?.roles || [];

                if (roles.includes('admin')) {
                    setIsAdmin(true);
                    alert(`Authenticated as ADMIN (${username})`);
                } else {
                    setIsAdmin(false);
                    // Check for viewer just for message specificity, though strictly not-admin implies restricted.
                    if (roles.includes('viewer')) {
                        alert(`Authenticated as VIEWER (${username}). Read-Only access.`);
                    } else {
                        // Default fallback if no specific role found
                        alert(`Authenticated as USER (${username}). Read-Only access.`);
                    }
                }
            } else {
                alert("Login failed: " + JSON.stringify(data));
            }
        } catch (e: any) {
            alert("Login Error: " + (e.message || e));
        }
    };

    const deleteNode = async (id: string) => {
        if (!confirm(`Delete node ${id}?`)) return;
        try {
            const res = await fetch(`${GATEWAY_URL}/api/nodes/${id}`, {
                method: 'DELETE',
                headers: { 'Authorization': `Bearer ${token}` }
            });
            if (res.status === 403) {
                alert("Access Denied: Admin privileges required.");
                return;
            }
            if (!res.ok) throw new Error(res.statusText);
            fetchNodes();
        } catch (e) {
            console.error(e);
            alert("Delete failed: " + e);
        }
    };

    const deleteAllNodes = async () => {
        if (!confirm("Delete ALL nodes? This cannot be undone.")) return;
        try {
            const res = await fetch(`${GATEWAY_URL}/api/nodes`, {
                method: 'DELETE',
                headers: { 'Authorization': `Bearer ${token}` }
            });
            if (res.status === 403) {
                alert("Access Denied: Admin privileges required.");
                return;
            }
            if (!res.ok) throw new Error(res.statusText);
            fetchNodes();
        } catch (e) {
            console.error(e);
            alert("Delete All failed: " + e);
        }
    }


    return (
        <div className="min-h-screen p-8 font-sans">
            <header className="mb-8 flex justify-between items-center">
                <div>
                    <h1 className="text-3xl font-bold flex items-center gap-2 text-cyan-400">
                        <Activity /> NodeSense Control Plane
                    </h1>
                    <p className="text-slate-400">Live Infrastructure Monitoring & Verification</p>
                </div>
                <div className="flex gap-4">
                    <button
                        onClick={getToken}
                        className={`px-4 py-2 rounded flex items-center gap-2 ${token ? 'bg-green-600' : 'bg-slate-700 hover:bg-slate-600'}`}>
                        <ShieldCheck size={18} /> {token ? (isAdmin ? 'Admin' : 'Viewer') : 'Login'}
                    </button>
                    <a href="http://127.0.0.1:3001/d/nodesense-main/nodesense-dashboard?orgId=1" target="_blank" className="px-4 py-2 bg-orange-600 rounded flex items-center gap-2 hover:bg-orange-500">
                        <Activity size={18} /> Open Grafana
                    </a>
                </div>
            </header>

            {/* Navigation Tabs */}
            <div className="flex gap-4 mb-8 border-b border-slate-700">
                <button
                    onClick={() => setView('dashboard')}
                    className={`pb-2 px-4 transition-colors ${view === 'dashboard' ? 'border-b-2 border-cyan-500 text-cyan-400' : 'text-slate-500 hover:text-slate-300'}`}>
                    Dashboard
                </button>
                {isAdmin && (
                    <button
                        onClick={() => setView('system')}
                        className={`pb-2 px-4 transition-colors flex items-center gap-2 ${view === 'system' ? 'border-b-2 border-cyan-500 text-cyan-400' : 'text-slate-500 hover:text-slate-300'}`}>
                        <Network size={16} /> System Topology
                    </button>
                )}
            </div>

            <main>
                {view === 'dashboard' && (
                    <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
                        {/* Sidebar Controls */}
                        <div className="lg:col-span-1 space-y-6">
                            <div className="bg-slate-800 p-6 rounded-xl border border-slate-700 shadow-lg">
                                <h2 className="text-xl font-semibold mb-4 flex items-center gap-2"><Smartphone size={20} /> Demo Simulator</h2>
                                <p className="text-sm text-slate-400 mb-4">Spawn virtual nodes to test data ingestion and metrics.</p>
                                <button
                                    onClick={simulateNode}
                                    className="w-full bg-cyan-600 hover:bg-cyan-500 text-white font-bold py-3 rounded flex justify-center items-center gap-2 transition-all active:scale-95">
                                    <Plus size={20} /> Add & Ping Node
                                </button>
                            </div>

                            <div className="bg-slate-800 p-6 rounded-xl border border-slate-700 shadow-lg">
                                <h2 className="text-xl font-semibold mb-4">System Status</h2>
                                <div className="space-y-2 text-sm">
                                    <div className="flex justify-between"><span>Gateway:</span> <span className="text-green-400">Online</span></div>
                                    <div className="flex justify-between"><span>Active Nodes:</span> <span className="font-mono text-cyan-300">{nodes.length}</span></div>
                                    {/* We could fetch replicas count here too if we had endpoint */}
                                </div>
                            </div>
                        </div>

                        {/* Node Grid */}
                        <div className="lg:col-span-3">
                            <div className="flex justify-between items-center mb-6">
                                <h2 className="text-2xl font-semibold">Active Nodes Topology</h2>
                                <div className="flex gap-2">
                                    {isAdmin && nodes.length > 0 && (
                                        <button onClick={deleteAllNodes} className="px-3 py-2 bg-red-900/50 hover:bg-red-900 text-red-200 rounded text-sm flex items-center gap-2">
                                            <Trash2 size={16} /> Clear All
                                        </button>
                                    )}
                                    <button onClick={fetchNodes} className="p-2 bg-slate-800 rounded hover:bg-slate-700"><RefreshCw size={18} /></button>
                                </div>
                            </div>

                            {nodes.length === 0 ? (
                                <div className="text-center p-12 bg-slate-800/50 rounded-xl border border-dashed border-slate-700 text-slate-500">
                                    No nodes detected. Try adding one!
                                </div>
                            ) : (
                                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                                    {nodes.map(node => (
                                        <div key={node.id} className="bg-slate-800 p-4 rounded-lg border border-slate-700 hover:border-cyan-500 transition-colors group cursor-pointer relative overflow-hidden">
                                            <div className="absolute top-0 right-0 p-2 opacity-50"><Server size={64} className="text-slate-700 group-hover:text-cyan-900 transition-colors" /></div>
                                            <div className="relative z-10">
                                                <h3 className="font-bold text-lg text-cyan-100">{node.name}</h3>
                                                <div className="text-xs text-slate-500 font-mono mb-2">{node.id}</div>
                                                <div className="text-sm flex items-center gap-2">
                                                    <div className={`w-2 h-2 rounded-full ${isAlive(node.last_seen) ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}></div>
                                                    {isAlive(node.last_seen) ? 'Online' : 'Offline / Silent'}
                                                </div>
                                                <div className="mt-2 text-xs text-slate-400">
                                                    Last seen: {new Date(node.last_seen).toLocaleTimeString()}
                                                </div>
                                            </div>
                                            {isAdmin && (
                                                <button
                                                    onClick={(e) => { e.stopPropagation(); deleteNode(node.id); }}
                                                    className="absolute top-2 right-2 text-slate-600 hover:text-red-500 bg-slate-900/50 p-1 rounded opacity-0 group-hover:opacity-100 transition-all"
                                                    title="Delete Node"
                                                >
                                                    <Trash2 size={16} />
                                                </button>
                                            )}
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>
                    </div>
                )}

                {/* SYSTEM VIEW */}
                {view === 'system' && isAdmin && (
                    <div className="space-y-6">
                        <div className="flex justify-between items-center">
                            <h2 className="text-2xl font-semibold">Docker Swarm Topology</h2>
                            <button onClick={fetchTopology} className="p-2 bg-slate-800 rounded hover:bg-slate-700"><RefreshCw size={18} /></button>
                        </div>

                        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                            {services.map(svc => (
                                <div
                                    key={svc.id}
                                    onClick={() => fetchLogs(svc.name)}
                                    className="bg-slate-800 p-6 rounded-xl border border-slate-700 hover:border-cyan-500 cursor-pointer transition-all hover:shadow-cyan-900/20 hover:shadow-lg relative overflow-hidden group">

                                    <div className="flex items-start justify-between">
                                        <div>
                                            <h3 className="font-bold text-lg text-white mb-1 group-hover:text-cyan-400 transition-colors">{svc.name}</h3>
                                            <div className="text-xs text-slate-500 font-mono truncate max-w-[200px] mb-4" title={svc.image}>{svc.image.split('@')[0]}</div>

                                            <div className="flex gap-2">
                                                <span className="px-2 py-1 rounded bg-slate-900 text-xs font-mono text-cyan-200 border border-slate-700">
                                                    Replicas: {svc.replicas === -1 ? 'Global' : svc.replicas}
                                                </span>
                                            </div>
                                        </div>
                                        <div className="p-3 bg-slate-700/50 rounded-lg group-hover:bg-cyan-900/20 transition-colors">
                                            <FileText size={24} className="text-slate-400 group-hover:text-cyan-400" />
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                )}
            </main>

            {/* Log Viewer Modal */}
            {selectedService && (
                <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4" onClick={() => setSelectedService(null)}>
                    <div className="bg-slate-900 w-full max-w-4xl max-h-[80vh] rounded-xl border border-slate-700 shadow-2xl flex flex-col" onClick={e => e.stopPropagation()}>
                        <div className="p-4 border-b border-slate-700 flex justify-between items-center bg-slate-800/50 rounded-t-xl">
                            <h3 className="font-bold text-lg text-cyan-400 flex items-center gap-2">
                                <FileText size={20} /> Logs: {selectedService}
                            </h3>
                            <button onClick={() => setSelectedService(null)} className="text-slate-400 hover:text-white">
                                <X size={24} />
                            </button>
                        </div>
                        <div className="flex-1 overflow-auto p-4 font-mono text-sm bg-black/50 text-slate-300 whitespace-pre-wrap">
                            {loadingLogs ? (
                                <div className="text-center py-12 text-slate-500 animate-pulse">Loading logs...</div>
                            ) : (
                                logs.length > 0 ? logs.map((line, i) => (
                                    <div key={i} className="border-b border-white/5 py-0.5 hover:bg-white/5 px-2">{line}</div>
                                )) : <div className="text-slate-500 italic">No logs available (or empty).</div>
                            )}
                        </div>
                    </div>
                </div>
            )}

            <AlertPopup token={token || ''} gatewayUrl={GATEWAY_URL} />
        </div>
    );
}

function isAlive(lastSeenVal: string) {
    const last = new Date(lastSeenVal).getTime();
    const now = new Date().getTime();
    return (now - last) < 120000; // 2 minutes
}

export default App;
