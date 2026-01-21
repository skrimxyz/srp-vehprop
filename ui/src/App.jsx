import React, { useState, useEffect, useCallback, useRef } from 'react';
import './styles.css';

const isInFiveM = window.GetParentResourceName && window.GetParentResourceName() !== 'srp-vehprop-dev';
const DEV_MODE = !isInFiveM;

if (DEV_MODE) {
    document.body.classList.add('dev-mode');
}

const App = () => {
    const [isOpen, setIsOpen] = useState(DEV_MODE);
    const [propInput, setPropInput] = useState('');
    const [attachedProps, setAttachedProps] = useState(DEV_MODE ? [
        { handle: 1, model: 'prop_lightbar_01', label: 'prop_lightbar_01', offset: { x: 0, y: 0, z: 0.5 }, rotation: { x: 0, y: 0, z: 0 } },
        { handle: 2, model: 'prop_roadcone01a', label: 'prop_roadcone01a', offset: { x: 0.5, y: 0, z: 0.3 }, rotation: { x: 0, y: 0, z: 45 } },
    ] : []);
    const [selectedProp, setSelectedProp] = useState(DEV_MODE ? 1 : null);
    const [gizmoMode, setGizmoMode] = useState('translate');
    const [isDragging, setIsDragging] = useState(false);
    const [dragAxis, setDragAxis] = useState(null);
    const [isFreecamActive, setIsFreecamActive] = useState(false);
    const [is3DDragging, setIs3DDragging] = useState(false);
    const [hoveredAxis, setHoveredAxis] = useState(null);
    const dragStartRef = useRef({ x: 0, y: 0 });
    const lastSentRef = useRef({ x: 0, y: 0 });

    useEffect(() => {
        const handleMessage = (event) => {
            const data = event.data;
            
            switch (data.action) {
                case 'open':
                    setIsOpen(true);
                    setGizmoMode(data.gizmoMode || 'translate');
                    break;
                case 'close':
                    setIsOpen(false);
                    break;
                case 'updateProps':
                    setAttachedProps(data.props || []);
                    setSelectedProp(data.selectedProp);
                    break;
                case 'updatePropPosition':
                    setAttachedProps(prevProps => 
                        prevProps.map(prop => 
                            prop.handle === data.handle 
                                ? { ...prop, offset: data.offset, rotation: data.rotation }
                                : prop
                        )
                    );
                    break;
                case 'showFreecamHint':
                    setIsFreecamActive(data.active);
                    break;
                case 'startDrag':
                    setIsDragging(true);
                    setDragAxis(data.axis);
                    break;
                case 'stopDrag':
                    setIsDragging(false);
                    setDragAxis(null);
                    break;
                case 'setHoveredAxis':
                    setHoveredAxis(data.axis);
                    break;
                case 'start3DDrag':
                    setIs3DDragging(true);
                    setDragAxis(data.axis);
                    dragStartRef.current = { x: data.mouseX, y: data.mouseY };
                    lastSentRef.current = { x: data.mouseX, y: data.mouseY };
                    break;
                case 'stop3DDrag':
                    setIs3DDragging(false);
                    setDragAxis(null);
                    break;
            }
        };

        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, []);

    useEffect(() => {
        const dragging = isDragging || is3DDragging;
        if (!dragging || !dragAxis) return;

        const handleMouseMove = (e) => {
            const deltaX = e.clientX - lastSentRef.current.x;
            const deltaY = e.clientY - lastSentRef.current.y;
            
            if (Math.abs(deltaX) > 2 || Math.abs(deltaY) > 2) {
                fetchNUI('gizmoDrag', { 
                    axis: dragAxis,
                    deltaX: e.clientX - dragStartRef.current.x,
                    deltaY: e.clientY - dragStartRef.current.y,
                    mode: gizmoMode
                });
                lastSentRef.current = { x: e.clientX, y: e.clientY };
            }
        };

        const handleMouseUp = () => {
            fetchNUI('gizmoDragEnd');
            setIsDragging(false);
            setIs3DDragging(false);
            setDragAxis(null);
        };

        window.addEventListener('mousemove', handleMouseMove);
        window.addEventListener('mouseup', handleMouseUp);
        
        return () => {
            window.removeEventListener('mousemove', handleMouseMove);
            window.removeEventListener('mouseup', handleMouseUp);
        };
    }, [isDragging, is3DDragging, dragAxis, gizmoMode]);

    useEffect(() => {
        const handleKeyDown = (e) => {
            if (e.key === 'Escape' && isOpen) {
                handleClose();
            }
            if (e.key === 'Shift' && isOpen) {
                fetchNUI('toggleFreecam');
            }
            
            if (isFreecamActive) {
                const key = e.key.toLowerCase();
                if (['w', 'a', 's', 'd', 'q', 'e'].includes(key)) {
                    fetchNUI('freecamKey', { key: key, pressed: true });
                }
            }
        };

        const handleKeyUp = (e) => {
            if (isFreecamActive) {
                const key = e.key.toLowerCase();
                if (['w', 'a', 's', 'd', 'q', 'e'].includes(key)) {
                    fetchNUI('freecamKey', { key: key, pressed: false });
                }
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        window.addEventListener('keyup', handleKeyUp);
        return () => {
            window.removeEventListener('keydown', handleKeyDown);
            window.removeEventListener('keyup', handleKeyUp);
        };
    }, [isOpen, isFreecamActive]);

    const fetchNUI = useCallback((event, data = {}) => {
        if (DEV_MODE) {
            console.log('[VehProp DEV] NUI Call:', event, data);
            return Promise.resolve();
        }
        return fetch(`https://srp-vehprop/${event}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
    }, []);

    const handleClose = () => {
        fetchNUI('close');
        setIsOpen(false);
    };

    const handleAddProp = () => {
        const model = propInput.trim();
        if (!model) return;
        
        fetchNUI('addProp', { model, label: model });
        setPropInput('');
    };

    const handleKeyPress = (e) => {
        if (e.key === 'Enter') {
            handleAddProp();
        }
    };

    const handleRemoveProp = (handle, e) => {
        e.stopPropagation();
        fetchNUI('removeProp', { handle });
        if (DEV_MODE) {
            setAttachedProps(prev => prev.filter(p => p.handle !== handle));
            if (selectedProp === handle) setSelectedProp(null);
        }
    };

    const handleSelectProp = (handle) => {
        fetchNUI('selectProp', { handle });
        if (DEV_MODE) {
            setSelectedProp(handle);
        }
    };

    const handleClearAll = () => {
        fetchNUI('clearAll');
        if (DEV_MODE) {
            setAttachedProps([]);
            setSelectedProp(null);
        }
    };

    const handleSaveExport = () => {
        fetchNUI('saveExport');
    };

    const handleGizmoModeChange = (mode) => {
        setGizmoMode(mode);
        fetchNUI('setGizmoMode', { mode });
    };

    const handleOverlayMouseDown = (e) => {
        if (isFreecamActive) return;
        if (!selectedProp) return;
        
        fetchNUI('checkGizmoClick', { 
            mouseX: e.clientX, 
            mouseY: e.clientY,
            screenW: window.innerWidth,
            screenH: window.innerHeight
        });
    };

    const handleOverlayMouseMove = (e) => {
        if (isFreecamActive) return;
        if (!selectedProp) return;
        if (is3DDragging) return;
        
        fetchNUI('checkGizmoHover', {
            mouseX: e.clientX,
            mouseY: e.clientY,
            screenW: window.innerWidth,
            screenH: window.innerHeight
        });
    };

    const handleMoveProp = (type, axis, direction) => {
        fetchNUI('moveProp', { type, axis, direction });
    };

    const handleResetAxis = (axis) => {
        fetchNUI('resetAxis', { type: gizmoMode, axis });
    };

    const handleAxisDragStart = (axis, e) => {
        e.preventDefault();
        setIsDragging(true);
        setDragAxis(axis);
        dragStartRef.current = { x: e.clientX, y: e.clientY };
        lastSentRef.current = { x: e.clientX, y: e.clientY };
        fetchNUI('gizmoDragStart', { axis, mode: gizmoMode });
    };

    const getSelectedPropData = () => {
        return attachedProps.find(p => p.handle === selectedProp);
    };

    if (!isOpen) return null;

    const selectedData = getSelectedPropData();

    return (
        <div className="terminal-overlay">
            {}
            {selectedProp && !isFreecamActive && (
                <div 
                    className={`gizmo-overlay ${is3DDragging ? 'dragging' : ''} ${hoveredAxis ? 'hovering hovering-' + hoveredAxis : ''}`}
                    onMouseDown={handleOverlayMouseDown}
                    onMouseMove={handleOverlayMouseMove}
                />
            )}
            
            <div className="terminal-container">
                {}
                <div className="terminal-header">
                    <div className="header-brand">
                        <div className="brand-icon">
                            <span className="icon-pulse"></span>
                            <svg viewBox="0 0 24 24" fill="currentColor">
                                <path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/>
                            </svg>
                        </div>
                        <div className="brand-text">
                            <span className="brand-title">VEHICLE PROPS</span>
                            <span className="brand-sub">Prop Attachment System</span>
                        </div>
                    </div>
                    
                    <button className="close-terminal" onClick={handleClose}>
                        <svg viewBox="0 0 24 24" fill="currentColor">
                            <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
                        </svg>
                    </button>
                </div>

                {}
                <div className="status-bar">
                    <div className="status-item">
                        <span className="status-dot online"></span>
                        <span>EDITOR ACTIVE</span>
                    </div>
                    <div className="status-divider"></div>
                    <div className="status-item">
                        <span className="status-icon">
                            <svg viewBox="0 0 24 24" fill="currentColor">
                                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                            </svg>
                        </span>
                        <span>Props: {attachedProps.length}</span>
                    </div>
                </div>

                {}
                <div className="terminal-content">
                    {}
                    <div className="content-section">
                        <div className="section-header">
                            <svg viewBox="0 0 24 24" fill="currentColor">
                                <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
                            </svg>
                            <span>Add Prop</span>
                        </div>
                        <div className="prop-input-row">
                            <input
                                type="text"
                                className="prop-input"
                                placeholder="Enter prop name (e.g. prop_lightbar_01)"
                                value={propInput}
                                onChange={(e) => setPropInput(e.target.value)}
                                onKeyPress={handleKeyPress}
                            />
                            <button className="add-prop-btn" onClick={handleAddProp}>
                                <svg viewBox="0 0 24 24" fill="currentColor">
                                    <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
                                </svg>
                            </button>
                        </div>
                    </div>

                    {}
                    <div className="content-section">
                        <div className="section-header">
                            <svg viewBox="0 0 24 24" fill="currentColor">
                                <path d="M3 13h2v-2H3v2zm0 4h2v-2H3v2zm0-8h2V7H3v2zm4 4h14v-2H7v2zm0 4h14v-2H7v2zM7 7v2h14V7H7z"/>
                            </svg>
                            <span>Attached Props ({attachedProps.length})</span>
                        </div>
                        
                        <div className="props-list">
                            {attachedProps.length === 0 ? (
                                <div className="empty-state">
                                    <svg viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
                                    </svg>
                                    <span>No props attached</span>
                                    <span className="hint">Enter a prop name and press Enter</span>
                                </div>
                            ) : (
                                attachedProps.map((prop) => (
                                    <div 
                                        className={`prop-card ${prop.handle === selectedProp ? 'selected' : ''}`}
                                        key={prop.handle}
                                        onClick={() => handleSelectProp(prop.handle)}
                                    >
                                        <div className="prop-icon">
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                                            </svg>
                                        </div>
                                        <div className="prop-info">
                                            <div className="prop-model">{prop.model}</div>
                                            <div className="prop-coords">
                                                X: {prop.offset?.x?.toFixed(2)} | Y: {prop.offset?.y?.toFixed(2)} | Z: {prop.offset?.z?.toFixed(2)}
                                            </div>
                                        </div>
                                        <button 
                                            className="delete-prop-btn"
                                            onClick={(e) => handleRemoveProp(prop.handle, e)}
                                        >
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
                                            </svg>
                                        </button>
                                    </div>
                                ))
                            )}
                        </div>
                    </div>

                    {}
                    {selectedProp && selectedData && (
                        <div className="content-section">
                            <div className="section-header">
                                <svg viewBox="0 0 24 24" fill="currentColor">
                                    <path d="M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3c-.46-4.17-3.77-7.48-7.94-7.94V1h-2v2.06C6.83 3.52 3.52 6.83 3.06 11H1v2h2.06c.46 4.17 3.77 7.48 7.94 7.94V23h2v-2.06c4.17-.46 7.48-3.77 7.94-7.94H23v-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z"/>
                                </svg>
                                <span>Gizmo Control</span>
                            </div>

                            {}
                            <div className="gizmo-mode-toggle">
                                <button 
                                    className={`mode-btn ${gizmoMode === 'translate' ? 'active' : ''}`}
                                    onClick={() => handleGizmoModeChange('translate')}
                                >
                                    <svg viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M10 9h4V6h3l-5-5-5 5h3v3zm-1 1H6V7l-5 5 5 5v-3h3v-4zm14 2l-5-5v3h-3v4h3v3l5-5zm-9 3h-4v3H7l5 5 5-5h-3v-3z"/>
                                    </svg>
                                    Position
                                </button>
                                <button 
                                    className={`mode-btn ${gizmoMode === 'rotate' ? 'active' : ''}`}
                                    onClick={() => handleGizmoModeChange('rotate')}
                                >
                                    <svg viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/>
                                    </svg>
                                    Rotation
                                </button>
                            </div>

                            {}
                            <div className="axis-controls">
                                <div className="axis-row x-axis">
                                    <span className="axis-label">X</span>
                                    <div className="axis-buttons">
                                        <button className="axis-btn" onClick={() => handleMoveProp(gizmoMode, 'x', -1)}>
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M19 13H5v-2h14v2z"/>
                                            </svg>
                                        </button>
                                        <div 
                                            className={`axis-drag-zone ${isDragging && dragAxis === 'x' ? 'dragging' : ''}`}
                                            onMouseDown={(e) => handleAxisDragStart('x', e)}
                                        >
                                            <span className="axis-value">
                                                {gizmoMode === 'translate' 
                                                    ? selectedData.offset?.x?.toFixed(3) || '0.000'
                                                    : (selectedData.rotation?.x?.toFixed(1) || '0.0') + '°'
                                                }
                                            </span>
                                            <span className="drag-hint">⟷ DRAG</span>
                                        </div>
                                        <button className="axis-btn" onClick={() => handleMoveProp(gizmoMode, 'x', 1)}>
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
                                            </svg>
                                        </button>
                                        <button className="axis-btn reset-btn" onClick={() => handleResetAxis('x')} title="Reset X">
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/>
                                            </svg>
                                        </button>
                                    </div>
                                </div>

                                <div className="axis-row y-axis">
                                    <span className="axis-label">Y</span>
                                    <div className="axis-buttons">
                                        <button className="axis-btn" onClick={() => handleMoveProp(gizmoMode, 'y', -1)}>
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M19 13H5v-2h14v2z"/>
                                            </svg>
                                        </button>
                                        <div 
                                            className={`axis-drag-zone ${isDragging && dragAxis === 'y' ? 'dragging' : ''}`}
                                            onMouseDown={(e) => handleAxisDragStart('y', e)}
                                        >
                                            <span className="axis-value">
                                                {gizmoMode === 'translate' 
                                                    ? selectedData.offset?.y?.toFixed(3) || '0.000'
                                                    : (selectedData.rotation?.y?.toFixed(1) || '0.0') + '°'
                                                }
                                            </span>
                                            <span className="drag-hint">⟷ DRAG</span>
                                        </div>
                                        <button className="axis-btn" onClick={() => handleMoveProp(gizmoMode, 'y', 1)}>
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
                                            </svg>
                                        </button>
                                        <button className="axis-btn reset-btn" onClick={() => handleResetAxis('y')} title="Reset Y">
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/>
                                            </svg>
                                        </button>
                                    </div>
                                </div>

                                <div className="axis-row z-axis">
                                    <span className="axis-label">Z</span>
                                    <div className="axis-buttons">
                                        <button className="axis-btn" onClick={() => handleMoveProp(gizmoMode, 'z', -1)}>
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M19 13H5v-2h14v2z"/>
                                            </svg>
                                        </button>
                                        <div 
                                            className={`axis-drag-zone ${isDragging && dragAxis === 'z' ? 'dragging' : ''}`}
                                            onMouseDown={(e) => handleAxisDragStart('z', e)}
                                        >
                                            <span className="axis-value">
                                                {gizmoMode === 'translate' 
                                                    ? selectedData.offset?.z?.toFixed(3) || '0.000'
                                                    : (selectedData.rotation?.z?.toFixed(1) || '0.0') + '°'
                                                }
                                            </span>
                                            <span className="drag-hint">⟷ DRAG</span>
                                        </div>
                                        <button className="axis-btn" onClick={() => handleMoveProp(gizmoMode, 'z', 1)}>
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
                                            </svg>
                                        </button>
                                        <button className="axis-btn reset-btn" onClick={() => handleResetAxis('z')} title="Reset Z">
                                            <svg viewBox="0 0 24 24" fill="currentColor">
                                                <path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/>
                                            </svg>
                                        </button>
                                    </div>
                                </div>
                            </div>

                            {}
                            <div className={`freecam-hint ${isFreecamActive ? 'active' : ''}`}>
                                <svg viewBox="0 0 24 24" fill="currentColor">
                                    <path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"/>
                                </svg>
                                <span>{isFreecamActive ? 'FREECAM - WASD/QE to move, SHIFT for cursor' : 'Press SHIFT for freecam'}</span>
                            </div>
                        </div>
                    )}
                </div>

                {}
                <div className="terminal-footer">
                    <button className="footer-btn danger" onClick={handleClearAll}>
                        <svg viewBox="0 0 24 24" fill="currentColor">
                            <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
                        </svg>
                        Clear All
                    </button>
                    <button className="footer-btn primary" onClick={handleSaveExport}>
                        <svg viewBox="0 0 24 24" fill="currentColor">
                            <path d="M17 3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V7l-4-4zm-5 16c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3zm3-10H5V5h10v4z"/>
                        </svg>
                        Save JSON
                    </button>
                </div>
            </div>
        </div>
    );
};

export default App;
