import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

import 'dapp_browser_service.dart';

class Web3ProviderInjector {
  static const _providerScript = '''
(function() {
  if (window.ethereum) return;
  
  class B2B2CProvider {
    constructor() {
      this.isB2B2C = true;
      this.isMetaMask = true;
      this.isStatus = true;
      this._events = {};
      this._requestId = 0;
      this._pendingRequests = new Map();
      window.addEventListener('message', this._handleMessage.bind(this));
    }
    
    async request(args) {
      return new Promise((resolve, reject) => {
        const id = ++this._requestId;
        const payload = {
          id: id.toString(),
          method: args.method,
          params: args.params || []
        };
        this._pendingRequests.set(id, { resolve, reject });
        
        window.flutter_inappwebview.callHandler('web3Request', JSON.stringify(payload))
          .catch(err => {
            this._pendingRequests.delete(id);
            reject(new Error(err.message || 'Request failed'));
          });
      });
    }
    
    _handleMessage(event) {
      if (event.data && event.data.type === 'web3Response') {
        const { id, result, error } = event.data;
        const pending = this._pendingRequests.get(parseInt(id));
        if (pending) {
          this._pendingRequests.delete(parseInt(id));
          if (error) pending.reject(new Error(error));
          else pending.resolve(result);
        }
      }
      if (event.data && event.data.type === 'web3Event') {
        this._emit(event.data.event, event.data.params);
      }
    }
    
    on(event, listener) {
      if (!this._events[event]) this._events[event] = [];
      this._events[event].push(listener);
      return this;
    }
    
    off(event, listener) {
      if (!this._events[event]) return;
      this._events[event] = this._events[event].filter(l => l !== listener);
      return this;
    }
    
    _emit(event, params) {
      if (!this._events[event]) return;
      this._events[event].forEach(listener => {
        try { listener(params); } catch (e) { console.error('Event listener error:', e); }
      });
    }
    
    emitEvent(event, params) { this._emit(event, params); }
    
    enable() { return this.request({ method: 'eth_requestAccounts' }); }
    
    send(methodOrPayload, callback) {
      if (typeof methodOrPayload === 'string') {
        return this.request({ method: methodOrPayload })
          .then(result => {
            if (callback) callback(null, { result });
            return { result };
          })
          .catch(error => {
            if (callback) callback(error, null);
            throw error;
          });
      }
      return this.request(methodOrPayload)
        .then(result => {
          if (callback) callback(null, { ...methodOrPayload, result });
          return { ...methodOrPayload, result };
        })
        .catch(error => {
          if (callback) callback(error, null);
          throw error;
        });
    }
    
    sendAsync(payload, callback) {
      return this.request(payload)
        .then(result => callback(null, { id: payload.id, jsonrpc: '2.0', result }))
        .catch(error => callback({ id: payload.id, jsonrpc: '2.0', error: { message: error.message } }, null));
    }
    
    isConnected() { return true; }
    get selectedAddress() { return this._selectedAddress; }
    get networkVersion() { return '1'; }
    get chainId() { return '0x1'; }
  }
  
  window.ethereum = new B2B2CProvider();
  window.web3 = { currentProvider: window.ethereum };
  window.__B2B2C_INJECTED__ = true;
})();
''';

  static String get providerScript => _providerScript;
}

class DAppBrowserController {
  final DAppBrowserService _service = DAppBrowserService();
  WebViewController? _webViewController;
  
  Function(DAppRequest)? onRequest;
  Function(String)? onUrlChange;
  Function(String)? onTitleChange;
  
  void attachWebViewController(WebViewController controller) {
    _webViewController = controller;
  }
  
  void detachWebViewController() {
    _webViewController = null;
  }
  
  Future<void> loadUrl(String url) async {
    await _webViewController?.loadRequest(Uri.parse(url));
  }
  
  Future<void> goBack() async {
    if (await _webViewController?.canGoBack() ?? false) {
      await _webViewController?.goBack();
    }
  }
  
  Future<void> goForward() async {
    if (await _webViewController?.canGoForward() ?? false) {
      await _webViewController?.goForward();
    }
  }
  
  Future<void> reload() async {
    await _webViewController?.reload();
  }
  
  Future<void> stop() async {
    await _webViewController?.loadRequest(Uri.parse('about:blank'));
  }
  
  Future<dynamic> evaluateJs(String script) async {
    return await _webViewController?.runJavaScript(script);
  }
  
  Future<void> injectProvider() async {
    await evaluateJs(Web3ProviderInjector.providerScript);
  }
  
  Future<void> emitAccountsChanged(List<String> accounts) async {
    await evaluateJs('''
      if (window.ethereum) {
        window.ethereum.emitEvent('accountsChanged', ${jsonEncode(accounts)});
      }
    ''');
  }
  
  Future<void> emitChainChanged(String chainId) async {
    await evaluateJs('''
      if (window.ethereum) {
        window.ethereum.emitEvent('chainChanged', '$chainId');
      }
    ''');
  }
  
  void dispose() {
    detachWebViewController();
    _service.dispose();
  }
}

extension on DAppResponse {
  Map<String, dynamic> toMap() => {
    'id': id,
    'success': success,
    'result': result,
    'error': error,
    'status': status.name,
  };
}
