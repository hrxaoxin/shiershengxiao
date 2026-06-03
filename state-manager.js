window.ZODIAC_STATE = (function() {
    const state = {
        account: null,
        chainId: null,
        isConnected: false,
        tokenBalance: 0,
        nftCount: 0,
        stakedCount: 0,
        rewards: 0,
        battlePoints: 0,
        seasonRank: 0,
        loading: false,
        error: null
    };

    const listeners = {};
    const PERSISTED_KEYS = ['account', 'chainId', 'tokenBalance', 'nftCount', 'stakedCount', 'dividendBalance'];

    function loadFromStorage() {
        try {
            const saved = localStorage.getItem('zodiac_state');
            if (saved) {
                const parsed = JSON.parse(saved);
                PERSISTED_KEYS.forEach(key => {
                    if (parsed[key] !== undefined) {
                        state[key] = parsed[key];
                    }
                });
            }
        } catch (e) {
            console.warn('Failed to load state from storage:', e);
        }
    }

    function saveToStorage() {
        try {
            const toSave = {};
            PERSISTED_KEYS.forEach(key => {
                toSave[key] = state[key];
            });
            localStorage.setItem('zodiac_state', JSON.stringify(toSave));
        } catch (e) {
            console.warn('Failed to save state to storage:', e);
        }
    }

    function set(key, value) {
        const oldValue = state[key];
        state[key] = value;
        
        if (PERSISTED_KEYS.includes(key)) {
            saveToStorage();
        }

        emit(key, { oldValue, newValue: value });
    }

    function get(key) {
        return state[key];
    }

    function getAll() {
        return { ...state };
    }

    function reset() {
        Object.keys(state).forEach(key => {
            if (key === 'account' || key === 'chainId') {
                state[key] = null;
            } else {
                const defaultValue = {
                    isConnected: false,
                    tokenBalance: 0,
                    nftCount: 0,
                    stakedCount: 0,
                    rewards: 0,
                    battlePoints: 0,
                    seasonRank: 0,
                    loading: false,
                    error: null
                };
                state[key] = defaultValue[key] || null;
            }
        });
        saveToStorage();
        emit('reset', state);
    }

    function on(key, callback) {
        if (!listeners[key]) {
            listeners[key] = [];
        }
        listeners[key].push(callback);
    }

    function emit(key, data) {
        if (!listeners[key]) return;
        listeners[key].forEach(cb => {
            try {
                cb(data);
            } catch (e) {
                console.error(`State listener error for ${key}:`, e);
            }
        });
    }

    function updateFromWeb3(account, chainId) {
        set('account', account);
        set('chainId', chainId);
        set('isConnected', !!account);
    }

    function setLoading(isLoading) {
        set('loading', isLoading);
    }

    function setError(error) {
        set('error', error);
        if (error) {
            setTimeout(() => set('error', null), 5000);
        }
    }

    loadFromStorage();

    return {
        set,
        get,
        getAll,
        reset,
        on,
        emit,
        updateFromWeb3,
        setLoading,
        setError
    };
})();