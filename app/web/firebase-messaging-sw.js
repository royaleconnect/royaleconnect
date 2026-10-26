// Royale Connect — receives phone/laptop notifications for the web app while the tab is closed.
// The Firebase web keys below are public by design (they only identify the project).
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA3VbQjT0bOEXFHTWfFVX_5P5erfSZP9j4',
  authDomain: 'royale-connect.firebaseapp.com',
  projectId: 'royale-connect',
  storageBucket: 'royale-connect.firebasestorage.app',
  messagingSenderId: '93672973250',
  appId: '1:93672973250:web:429ff96e5742a622faac5b',
});
firebase.messaging();   // shows the notification; a click opens the page given by the server

// take over straight away (this also retires the old offline-cache worker from earlier versions)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
