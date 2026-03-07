// Nano Voice Interface — WebSocket + Web Speech API + HAL 9000 Eye

(function () {
    'use strict';

    // --- Session ---
    const sessionId = crypto.randomUUID();

    // --- WebSocket ---
    let ws = null;
    let reconnectAttempts = 0;
    const MAX_RECONNECT_DELAY = 30000;

    // --- DOM ---
    const body = document.body;
    const orbContainer = document.getElementById('orbContainer');
    const status = document.getElementById('status');
    const transcript = document.getElementById('transcript');
    const history = document.getElementById('history');
    const textFallback = document.getElementById('textFallback');
    const textInput = document.getElementById('textInput');
    const textSend = document.getElementById('textSend');
    const ttsAudio = document.getElementById('ttsAudio');
    const errorToast = document.getElementById('errorToast');

    // --- State ---
    let state = 'disconnected'; // disconnected | idle | listening | processing | speaking
    let recognition = null;
    let finalTranscript = '';
    let interimTranscript = '';
    let userRequestedStop = false;
    let pendingUserText = null; // text waiting for response

    // --- Web Speech API Setup ---
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    const speechSupported = !!SpeechRecognition;
    let recognitionActive = false;

    console.log('[Nano] Speech API supported:', speechSupported);

    // Always show text input
    textFallback.classList.add('visible');

    // --- WebSocket Connection ---
    function connectWebSocket() {
        const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = protocol + '//' + location.host + '/?session=' + sessionId;

        console.log('[Nano] Connecting to', wsUrl);
        setState('disconnected');

        ws = new WebSocket(wsUrl);

        ws.onopen = function () {
            console.log('[Nano] WebSocket connected');
            reconnectAttempts = 0;
        };

        ws.onmessage = function (event) {
            try {
                var data = JSON.parse(event.data);
                handleServerMessage(data);
            } catch (err) {
                console.warn('[Nano] Invalid message:', err);
            }
        };

        ws.onclose = function (event) {
            console.log('[Nano] WebSocket closed:', event.code, event.reason);
            ws = null;
            setState('disconnected');
            scheduleReconnect();
        };

        ws.onerror = function (err) {
            console.error('[Nano] WebSocket error:', err);
        };
    }

    function scheduleReconnect() {
        var delay = Math.min(1000 * Math.pow(2, reconnectAttempts), MAX_RECONNECT_DELAY);
        reconnectAttempts++;
        console.log('[Nano] Reconnecting in', delay, 'ms (attempt', reconnectAttempts + ')');
        setTimeout(connectWebSocket, delay);
    }

    function handleServerMessage(data) {
        switch (data.type) {
            case 'connected':
                console.log('[Nano] Server confirmed connection, session:', data.sessionId);
                setState('idle');
                break;

            case 'text':
                // Agent response text
                if (pendingUserText) {
                    addExchange(pendingUserText, data.text);
                    pendingUserText = null;
                } else {
                    addExchange('', data.text);
                }
                // Stay in processing if audio might follow, otherwise go idle
                if (state === 'processing') {
                    // Brief delay — if no audio arrives, go idle
                    setTimeout(function () {
                        if (state === 'processing') setState('idle');
                    }, 500);
                }
                break;

            case 'audio':
                // TTS audio from server
                if (data.audio_base64) {
                    playAudio(data.audio_base64);
                }
                break;

            case 'typing':
                if (data.isTyping && state !== 'processing' && state !== 'speaking') {
                    setState('processing');
                }
                break;

            default:
                console.log('[Nano] Unknown message type:', data.type);
        }
    }

    // --- State Machine ---
    function setState(newState) {
        state = newState;
        body.className = 'state-' + newState;

        var labels = {
            disconnected: 'Verbinde...',
            idle: 'Bereit',
            listening: 'Hoere zu...',
            processing: 'Denke nach...',
            speaking: 'Spreche...',
        };
        status.textContent = labels[newState] || '';
    }

    // --- Orb Click Handler ---
    orbContainer.addEventListener('click', function () {
        switch (state) {
            case 'idle':
                if (speechSupported) {
                    startListening();
                }
                break;
            case 'listening':
                stopListening();
                break;
            case 'speaking':
                stopSpeaking();
                break;
            case 'processing':
            case 'disconnected':
                // Do nothing
                break;
        }
    });

    // --- Speech Recognition ---
    function initRecognition() {
        if (!speechSupported) return;

        recognition = new SpeechRecognition();
        recognition.lang = 'de-DE';
        recognition.continuous = true;
        recognition.interimResults = true;
        recognition.maxAlternatives = 1;

        recognition.onstart = function () {
            console.log('[Nano] Recognition started');
            recognitionActive = true;
            setState('listening');
        };

        recognition.onresult = function (event) {
            interimTranscript = '';
            for (var i = event.resultIndex; i < event.results.length; i++) {
                var t = event.results[i][0].transcript;
                if (event.results[i].isFinal) {
                    finalTranscript += t + ' ';
                } else {
                    interimTranscript = t;
                }
            }
            showTranscript(finalTranscript + interimTranscript);
        };

        recognition.onerror = function (event) {
            console.warn('[Nano] Recognition error:', event.error);
            if (event.error === 'no-speech') {
                return; // Will auto-restart in onend
            }
            if (event.error === 'aborted') return;

            if (event.error === 'not-allowed') {
                showError('Mikrofon-Zugriff verweigert');
            } else if (event.error === 'network') {
                showError('Netzwerkfehler bei Spracherkennung');
            } else {
                showError('Spracherkennung: ' + event.error);
            }
            recognitionActive = false;
            setState('idle');
        };

        recognition.onend = function () {
            console.log('[Nano] Recognition ended. State:', state, 'userStop:', userRequestedStop);
            recognitionActive = false;

            if (state !== 'listening') return;

            if (userRequestedStop) {
                var text = finalTranscript.trim();
                if (text) {
                    sendMessage(text);
                } else {
                    setState('idle');
                    hideTranscript();
                }
            } else {
                // Auto-restart on no-speech timeout
                setTimeout(function () {
                    if (state === 'listening') {
                        initRecognition();
                        try { recognition.start(); } catch (e) {
                            console.error('[Nano] Restart failed:', e);
                            setState('idle');
                        }
                    }
                }, 100);
            }
        };
    }

    function startListening() {
        finalTranscript = '';
        interimTranscript = '';
        userRequestedStop = false;
        showTranscript('');
        initRecognition();

        try {
            recognition.start();
        } catch (e) {
            console.error('[Nano] Start failed:', e);
            try { recognition.abort(); } catch (_) {}
            setTimeout(function () {
                initRecognition();
                try { recognition.start(); } catch (e2) {
                    showError('Spracherkennung konnte nicht gestartet werden');
                    setState('idle');
                }
            }, 200);
        }
    }

    function stopListening() {
        userRequestedStop = true;
        if (recognition && recognitionActive) {
            try { recognition.stop(); } catch (_) {}
        } else {
            var text = finalTranscript.trim();
            if (text) {
                sendMessage(text);
            } else {
                setState('idle');
                hideTranscript();
            }
        }
    }

    // --- Send Message via WebSocket ---
    function sendMessage(text) {
        console.log('[Nano] sendMessage:', text);

        if (!ws || ws.readyState !== WebSocket.OPEN) {
            showError('Nicht verbunden');
            setState('idle');
            return;
        }

        setState('processing');
        hideTranscript();
        pendingUserText = text;

        ws.send(JSON.stringify({ type: 'message', text: text }));
    }

    // --- Audio Playback ---
    function playAudio(base64) {
        setState('speaking');
        ttsAudio.src = 'data:audio/ogg;base64,' + base64;
        ttsAudio.play().catch(function () {
            setState('idle');
        });
    }

    ttsAudio.addEventListener('ended', function () {
        setState('idle');
    });

    ttsAudio.addEventListener('error', function () {
        setState('idle');
    });

    function stopSpeaking() {
        ttsAudio.pause();
        ttsAudio.currentTime = 0;
        setState('idle');
    }

    // --- Transcript Display ---
    function showTranscript(text) {
        transcript.textContent = text;
        transcript.classList.toggle('visible', !!text);
    }

    function hideTranscript() {
        transcript.classList.remove('visible');
    }

    // --- Chat History ---
    function addExchange(userText, assistantText) {
        var el = document.createElement('div');
        el.className = 'exchange';
        var html = '';
        if (userText) {
            html += '<div class="exchange-user">' + escapeHtml(userText) + '</div>';
        }
        html += '<div class="exchange-assistant">' + escapeHtml(assistantText) + '</div>';
        el.innerHTML = html;
        history.prepend(el);
    }

    function escapeHtml(text) {
        var div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // --- Text Input Fallback ---
    textSend.addEventListener('click', function () {
        var text = textInput.value.trim();
        if (text) {
            textInput.value = '';
            sendMessage(text);
        }
    });

    textInput.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') {
            textSend.click();
        }
    });

    // --- Error Toast ---
    var errorTimeout = null;
    function showError(msg) {
        errorToast.textContent = msg;
        errorToast.classList.add('visible');
        clearTimeout(errorTimeout);
        errorTimeout = setTimeout(function () {
            errorToast.classList.remove('visible');
        }, 4000);
    }

    // --- Keyboard shortcut: Space to toggle ---
    document.addEventListener('keydown', function (e) {
        if (e.target.tagName === 'INPUT') return;
        if (e.code === 'Space') {
            e.preventDefault();
            orbContainer.click();
        }
    });

    // --- Start ---
    connectWebSocket();

})();
