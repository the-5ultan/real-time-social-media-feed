class FeedDashboard {
    constructor() {
        this.apiBase = '';
        this.autoRefresh = true;
        this.refreshInterval = null;
        this.logFilter = 'ALL';
        this.init();
    }

    init() {
        this.bindEvents();
        this.checkSystemStatus();
        this.loadInitialData();
    }

    bindEvents() {
        document.getElementById('autoRefreshCheck').addEventListener('change', (e) => {
            this.autoRefresh = e.target.checked;
            if (this.autoRefresh) {
                this.startAutoRefresh();
            } else {
                this.stopAutoRefresh();
            }
        });
    }

    async apiCall(endpoint, options = {}) {
        try {
            const response = await fetch(`${this.apiBase}${endpoint}`, {
                headers: { 'Content-Type': 'application/json' },
                ...options
            });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return await response.json();
        } catch (error) {
            console.error(`API call failed: ${endpoint}`, error);
            return null;
        }
    }

    async executeCommand(cmd, args = '') {
        return this.apiCall('/api/command', {
            method: 'POST',
            body: JSON.stringify({ command: cmd, args })
        });
    }

    async checkSystemStatus() {
        const status = await this.apiCall('/api/status');
        this.updateSystemStatus(status);
        return status;
    }

    updateSystemStatus(status) {
        const statusEl = document.getElementById('systemStatus');
        const startBtn = document.getElementById('startSystemBtn');
        const stopBtn = document.getElementById('stopSystemBtn');
        const simBtns = document.querySelectorAll('#startSimBtn, #stopSimBtn, #burstBtn');
        const procBtns = document.querySelectorAll('#addProducerBtn, #removeProducerBtn, #addWorkerBtn, #removeWorkerBtn');
        const eventBtn = document.getElementById('createEventBtn');

        if (status && status.manager && status.manager.status === 'RUNNING') {
            statusEl.innerHTML = '<span class="status-dot running"></span><span>System: Running</span>';
            startBtn.disabled = true;
            stopBtn.disabled = false;
            simBtns.forEach(b => b.disabled = false);
            procBtns.forEach(b => b.disabled = false);
            eventBtn.disabled = false;
            this.startAutoRefresh();
        } else {
            statusEl.innerHTML = '<span class="status-dot stopped"></span><span>System: Stopped</span>';
            startBtn.disabled = false;
            stopBtn.disabled = true;
            simBtns.forEach(b => b.disabled = true);
            procBtns.forEach(b => b.disabled = true);
            eventBtn.disabled = true;
            this.stopAutoRefresh();
        }
    }

    startAutoRefresh() {
        if (this.refreshInterval) return;
        this.refreshInterval = setInterval(() => {
            if (this.autoRefresh) this.refreshAll();
        }, 1000);
    }

    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
    }

    toggleAutoRefresh() {
        this.autoRefresh = document.getElementById('autoRefreshCheck').checked;
        if (this.autoRefresh) this.startAutoRefresh();
        else this.stopAutoRefresh();
    }

    async loadInitialData() {
        await Promise.all([
            this.loadFeed(),
            this.loadProcesses(),
            this.loadQueue(),
            this.loadStatistics(),
            this.loadResources(),
            this.loadLogs()
        ]);
    }

    async refreshAll() {
        await Promise.all([
            this.loadFeed(),
            this.loadProcesses(),
            this.loadQueue(),
            this.loadStatistics(),
            this.loadResources(),
            this.loadLogs()
        ]);
    }

    async startSystem() {
        const result = await this.executeCommand('start');
        if (result && result.success) {
            this.showNotification('System started successfully', 'success');
            setTimeout(() => this.checkSystemStatus(), 1000);
        } else {
            this.showNotification('Failed to start system', 'error');
        }
    }

    async stopSystem() {
        const result = await this.executeCommand('stop');
        if (result && result.success) {
            this.showNotification('System stopped', 'success');
            setTimeout(() => this.checkSystemStatus(), 1000);
        } else {
            this.showNotification('Failed to stop system', 'error');
        }
    }

    async startSimulation() {
        const result = await this.executeCommand('simulate start');
        if (result && result.success) {
            this.showNotification('Simulation started', 'success');
        } else {
            this.showNotification('Failed to start simulation', 'error');
        }
    }

    async stopSimulation() {
        const result = await this.executeCommand('simulate stop');
        if (result && result.success) {
            this.showNotification('Simulation stopped', 'success');
        } else {
            this.showNotification('Failed to stop simulation', 'error');
        }
    }

    async generateBurst() {
        const result = await this.executeCommand('simulate burst');
        if (result && result.success) {
            this.showNotification('Burst generated', 'success');
            setTimeout(() => this.refreshAll(), 500);
        } else {
            this.showNotification('Failed to generate burst', 'error');
        }
    }

    async addProducer() {
        const result = await this.executeCommand('add producer');
        if (result && result.success) {
            this.showNotification('Producer added', 'success');
            setTimeout(() => this.loadProcesses(), 500);
        } else {
            this.showNotification('Failed to add producer', 'error');
        }
    }

    async removeProducer() {
        const result = await this.executeCommand('remove producer');
        if (result && result.success) {
            this.showNotification('Producer removed', 'success');
            setTimeout(() => this.loadProcesses(), 500);
        } else {
            this.showNotification('Failed to remove producer', 'error');
        }
    }

    async addWorker() {
        const result = await this.executeCommand('add worker');
        if (result && result.success) {
            this.showNotification('Worker added', 'success');
            setTimeout(() => this.loadProcesses(), 500);
        } else {
            this.showNotification('Failed to add worker', 'error');
        }
    }

    async removeWorker() {
        const result = await this.executeCommand('remove worker');
        if (result && result.success) {
            this.showNotification('Worker removed', 'success');
            setTimeout(() => this.loadProcesses(), 500);
        } else {
            this.showNotification('Failed to remove worker', 'error');
        }
    }

    async createManualEvent() {
        const type = document.getElementById('eventTypeSelect').value;
        const content = document.getElementById('eventContentInput').value;
        
        const result = await this.executeCommand('event', `${type} ${content}`);
        if (result && result.success) {
            this.showNotification(`Event created: ${type}`, 'success');
            document.getElementById('eventContentInput').value = '';
            setTimeout(() => this.refreshAll(), 500);
        } else {
            this.showNotification('Failed to create event', 'error');
        }
    }

    async loadFeed() {
        const data = await this.apiCall('/api/feed');
        this.renderFeed(data);
    }

    renderFeed(data) {
        const container = document.getElementById('feedContainer');
        const statsEl = document.getElementById('feedStats');

        if (!data) {
            container.innerHTML = '<div class="loading">Failed to load feed</div>';
            return;
        }

        if (data.posts && data.posts.length > 0) {
            let html = '';
            data.posts.forEach(post => {
                const time = new Date(post.timestamp).toLocaleTimeString();
                html += `
                    <div class="post-card">
                        <div class="post-header">
                            <span class="post-author">@${post.username || post.user_id}</span>
                            <span class="post-time">${time}</span>
                        </div>
                        <div class="post-content">${this.escapeHtml(post.content)}</div>
                        <div class="post-meta">
                            <span>❤️ ${post.likes || 0}</span>
                            <span>💬 ${post.comments || 0}</span>
                            <span>🔄 ${post.shares || 0}</span>
                        </div>
                    </div>
                `;
            });
            container.innerHTML = html;
        } else {
            container.innerHTML = '<div class="loading">No posts yet. Start the system and simulation to see posts!</div>';
        }

        if (data.stats) {
            statsEl.textContent = `${data.stats.total_posts || 0} posts • ${data.stats.total_likes || 0} likes • ${data.stats.total_comments || 0} comments • ${data.stats.total_shares || 0} shares`;
        }
    }

    async loadProcesses() {
        const data = await this.apiCall('/api/processes');
        this.renderProcesses(data);
    }

    renderProcesses(data) {
        const tbody = document.querySelector('#processTable tbody');
        if (!data || !data.length) {
            tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-muted)">No processes</td></tr>';
            return;
        }

        tbody.innerHTML = data.map(proc => `
            <tr>
                <td>${this.escapeHtml(proc.name)}</td>
                <td>${this.escapeHtml(proc.type)}</td>
                <td>${proc.pid}</td>
                <td><span class="status-badge ${proc.status.toLowerCase()}">${proc.status}</span></td>
                <td>${proc.events_processed || 0}</td>
                <td>${proc.start_time || '-'}</td>
            </tr>
        `).join('');
    }

    async loadQueue() {
        const data = await this.apiCall('/api/queue');
        this.renderQueue(data);
    }

    renderQueue(data) {
        const tbody = document.querySelector('#queueTable tbody');
        const statsEl = document.getElementById('queueStats');

        if (!data) {
            tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-muted)">Failed to load queue</td></tr>';
            return;
        }

        statsEl.textContent = `Size: ${data.size || 0} • By Type: ${JSON.stringify(data.by_type || {})} • By Priority: ${JSON.stringify(data.by_priority || {})}`;

        if (data.events && data.events.length > 0) {
            tbody.innerHTML = data.events.map(event => `
                <tr>
                    <td>${this.escapeHtml(event.event_id)}</td>
                    <td>${this.escapeHtml(event.event_type)}</td>
                    <td>${this.escapeHtml(event.user_name)}</td>
                    <td><span class="priority-badge priority-${event.priority}">${event.priority}</span></td>
                    <td><span class="status-badge ${event.status.toLowerCase()}">${event.status}</span></td>
                    <td>${event.timestamp}</td>
                </tr>
            `).join('');
        } else {
            tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-muted)">Queue empty</td></tr>';
        }
    }

    async loadStatistics() {
        const data = await this.apiCall('/api/stats');
        this.renderStatistics(data);
    }

    renderStatistics(data) {
        if (!data) return;

        const mappings = {
            'statTotalEvents': 'total_events',
            'statProcessed': 'processed_events',
            'statPending': 'pending_events',
            'statPosts': 'total_posts',
            'statLikes': 'total_likes',
            'statComments': 'total_comments',
            'statShares': 'total_shares',
            'statFollows': 'total_follows',
            'statProducers': 'active_producers',
            'statWorkers': 'active_workers',
            'statRate': 'processing_rate',
            'statUptime': 'uptime_formatted'
        };

        Object.entries(mappings).forEach(([id, key]) => {
            const el = document.getElementById(id);
            if (el && data[key] !== undefined) {
                el.textContent = data[key];
            }
        });
    }

    async loadResources() {
        const data = await this.apiCall('/api/resources');
        this.renderResources(data);
    }

    renderResources(data) {
        if (!data) return;

        const cpuEl = document.getElementById('resCpu');
        const memEl = document.getElementById('resMem');
        const diskEl = document.getElementById('resDisk');
        const procsEl = document.getElementById('resProcs');
        const loadEl = document.getElementById('resLoad');
        const uptimeEl = document.getElementById('resUptime');

        if (cpuEl) cpuEl.textContent = `${data.cpu_usage_percent || 0}%`;
        if (memEl) memEl.textContent = `${data.memory?.usage_percent || 0}%`;
        if (diskEl) diskEl.textContent = `${data.disk?.usage_percent || 0}%`;
        if (procsEl) procsEl.textContent = data.processes?.total || 0;
        if (loadEl) loadEl.textContent = data.load_average?.['1min'] || '0.00';
        if (uptimeEl) uptimeEl.textContent = data.uptime?.formatted || '-';
    }

    async loadLogs() {
        const data = await this.apiCall(`/api/logs?category=${this.logFilter}&lines=100`);
        this.renderLogs(data);
    }

    filterLogs() {
        this.logFilter = document.getElementById('logCategorySelect').value;
        this.loadLogs();
    }

    renderLogs(data) {
        const container = document.getElementById('logContainer');
        if (!data || !data.length) {
            container.innerHTML = '<div class="loading">No logs</div>';
            return;
        }

        container.innerHTML = data.map(log => {
            const category = (log.CATEGORY || 'SYSTEM').toLowerCase();
            const level = (log.LEVEL || 'INFO').toUpperCase();
            return `
                <div class="log-entry ${category}">
                    <span class="log-time">${log.timestamp || ''}</span>
                    <span class="log-pid">PID=${log.PID || ''}</span>
                    <span class="log-user">USER=${log.USER || ''}</span>
                    <span class="log-category">${log.CATEGORY || ''}</span>
                    <span class="log-level ${level}">${level}</span>
                    <span class="log-message">${this.escapeHtml(log.MSG || '')}</span>
                    ${log.EVENT_ID ? `<span class="log-event_id">EVENT_ID=${log.EVENT_ID}</span>` : ''}
                    ${log.EVENT_TYPE ? `<span class="log-event_type">TYPE=${log.EVENT_TYPE}</span>` : ''}
                    ${log.STATUS ? `<span class="log-status">STATUS=${log.STATUS}</span>` : ''}
                </div>
            `;
        }).join('');
        
        container.scrollTop = container.scrollHeight;
    }

    async clearLogs() {
        await this.executeCommand('clear logs');
        this.loadLogs();
    }

    showNotification(message, type = 'info') {
        const notification = document.createElement('div');
        notification.className = `notification ${type}`;
        notification.textContent = message;
        notification.style.cssText = `
            position: fixed; top: 20px; right: 20px; z-index: 1000;
            padding: 12px 20px; border-radius: 6px; font-size: 0.85rem;
            background: ${type === 'success' ? '#10b981' : type === 'error' ? '#ef4444' : '#2563eb'};
            color: white; box-shadow: var(--shadow); animation: slideIn 0.3s ease;
        `;
        document.body.appendChild(notification);
        setTimeout(() => {
            notification.style.animation = 'slideOut 0.3s ease';
            setTimeout(() => notification.remove(), 300);
        }, 3000);
    }

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

document.addEventListener('DOMContentLoaded', () => {
    window.dashboard = new FeedDashboard();
});

// Add notification animations
const style = document.createElement('style');
style.textContent = `
    @keyframes slideIn { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
    @keyframes slideOut { from { transform: translateX(0); opacity: 1; } to { transform: translateX(100%); opacity: 0; } }
`;
document.head.appendChild(style);