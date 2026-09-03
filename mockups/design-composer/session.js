/* RaajjePro prototype session — shared across all screens.
   Role + walk-through state persist in localStorage; the seed is the single
   source of demo data (§5, Round 38). If storage is unavailable the app
   behaves as role "customer" with the artboards' own data. */
(function () {
  var KEY = 'rp.session.v1';
  function load() { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; } }
  function save(s) { try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) {} }

  var seed = {
    personas: {
      customer: {
        name: 'Aishath Naeema', initials: 'AN', island: 'Malé',
        addresses: [
          { label: 'Home', line: 'M. Fehivina, 3rd floor, Kalaafaanu Hingun, Malé' },
          { label: 'Office', line: 'H. Orchid Lodge, Unit 2B, Nirolhu Magu, Hulhumalé' }
        ],
        windows: ['Weekdays 9:00–12:00', 'Saturday 14:00–18:00'],
        instruction: 'Gate code 4471. Please call from the lobby.'
      },
      provider: {
        name: 'Ibrahim Rasheed', initials: 'IR', business: 'Rasheed Plumbing Services',
        tier: 'Gold', rating: '4.6', reviews: 31, jobs: 47, replyTime: '12 min',
        island: 'Malé', category: 'Plumbing',
        conduct: { completed: 94, cancelled: 3, noShow: 2, onTime: 91, priceHonoured: 97 }
      }
    },
    // slot ("Pick a time") only for Cleaning, Beauty, Fitness. Callback guarantee and
    // emergency cover follow the category rules exactly.
    categories: [
      { name: 'Cleaning', mode: 'slot' },
      { name: 'Beauty', mode: 'slot' },
      { name: 'Fitness', mode: 'slot' },
      { name: 'Plumbing', mode: 'request', callback: true, emergency: 'Gold' },
      { name: 'Electrical', mode: 'request', callback: true, emergency: 'Gold' },
      { name: 'AC Repair', mode: 'request', callback: true, emergency: 'Silver' },
      { name: 'Appliance Repair', mode: 'request', callback: true },
      { name: 'Pest Control', mode: 'request', callback: true },
      { name: 'Photography', mode: 'request' },
      { name: 'Moving', mode: 'request', emergency: 'Silver' },
      { name: 'Home Repairs', mode: 'request', callback: true },
      { name: 'Boat Charter', mode: 'request' }
    ],
    emergencyWindowMin: 30, // all four emergency categories
    listings: [
      { id: 'clean-1', title: 'Home Deep Cleaning', provider: 'Mariyam Shifa', cat: 'Cleaning', tier: 'Silver', rating: '4.8', count: 24, price: 'MVR 450', unit: '/session', island: 'Malé', mode: 'slot', nextSlot: 'tomorrow 09:00' },
      { id: 'plumb-1', title: 'Emergency Plumbing & Pipe Repair', provider: 'Ibrahim Rasheed', cat: 'Plumbing', tier: 'Gold', rating: '4.6', count: 31, price: 'From MVR 350', unit: '', island: 'Malé', mode: 'request', callback: true, replyTime: '12 min', bookings: 44 },
      { id: 'plumb-2', title: 'Bathroom & Kitchen Plumbing Installation', provider: 'Ibrahim Rasheed', cat: 'Plumbing', tier: 'Gold', rating: '4.6', count: 31, price: 'MVR 900', unit: '/day', island: 'Malé', mode: 'request', callback: false },
      { id: 'plumb-3', title: 'Drain Cleaning & Unblocking', provider: 'Naseem Ali', cat: 'Plumbing', tier: 'Gold', rating: '4.3', count: 22, price: 'MVR 350', unit: '/visit', island: 'Malé', mode: 'request', callback: false, replyTime: '45 min', bookings: 22 },
      { id: 'plumb-4', title: 'Water Pump Install & Repair', provider: 'AquaFix Maldives', cat: 'Plumbing', tier: 'Gold', rating: '4.5', count: 14, price: 'From MVR 450', unit: '', island: 'Malé', mode: 'request', callback: true, replyTime: '1 hr', bookings: 16 },
      { id: 'ac-1', title: 'AC Servicing & Gas Refill', provider: 'Ahmed Shakir', cat: 'AC Repair', tier: 'Silver', rating: '4.4', count: 12, price: 'MVR 600', unit: '/visit', island: 'Hulhumalé', mode: 'request', callback: true, replyTime: '25 min', bookings: 20 },
      { id: 'photo-1', title: 'Event & Wedding Photography', provider: 'Hussain Nizar', cat: 'Photography', tier: 'Gold', rating: '4.9', count: 58, price: 'From MVR 2500', unit: '', island: 'Malé', mode: 'request', replyTime: '2 hr', bookings: 58 },
      { id: 'beauty-1', title: 'Bridal Makeup & Styling', provider: 'Aishath Leela', cat: 'Beauty', tier: 'Silver', rating: '4.9', count: 86, price: 'MVR 800', unit: '/session', island: 'Malé', mode: 'slot', nextSlot: 'today 16:00' },
      { id: 'pest-1', title: 'Home Pest Treatment', provider: 'Adam Naseer', cat: 'Pest Control', tier: null, rating: '4.5', count: 9, price: 'MVR 300', unit: '/visit', island: 'Hulhumalé', mode: 'request', callback: true, bookings: 7 },
      { id: 'move-1', title: 'House & Office Moving', provider: 'Moosa Rilwan', cat: 'Moving', tier: 'Bronze', rating: '4.3', count: 21, price: 'From MVR 1500', unit: '', island: 'Malé', mode: 'request', replyTime: '3 hr', bookings: 21 },
      { id: 'appl-1', title: 'Appliance & Computer Repair', provider: 'Island Tech Solutions', cat: 'Appliance Repair', tier: 'Gold', rating: '4.7', count: 186, price: 'From MVR 200', unit: '', island: 'Malé', mode: 'request', callback: true, replyTime: '40 min', bookings: 186 },
      { id: 'elec-1', title: 'Wiring & Fault Repair', provider: 'Ali Waheed', cat: 'Electrical', tier: 'Silver', rating: '4.5', count: 18, price: 'From MVR 250', unit: '', island: 'Malé', mode: 'request', callback: true, replyTime: '30 min', bookings: 26 },
      { id: 'fit-1', title: 'Personal Training Sessions', provider: 'Fathimath Riza', cat: 'Fitness', tier: 'Bronze', rating: '4.7', count: 14, price: 'MVR 200', unit: '/session', island: 'Hulhumalé', mode: 'slot', nextSlot: 'tomorrow 06:30' },
      { id: 'rep-1', title: 'General Home Repairs & Carpentry', provider: 'Hassan Zahir', cat: 'Home Repairs', tier: 'Silver', rating: '4.6', count: 22, price: 'From MVR 300', unit: '', island: 'Malé', mode: 'request', callback: true, replyTime: '1 hr', bookings: 30 },
      { id: 'boat-1', title: 'Sunset Fishing Charter', provider: 'Ahmed Faisal', cat: 'Boat Charter', tier: 'Bronze', rating: '4.8', count: 11, price: 'MVR 3200', unit: '/trip', island: 'Malé', mode: 'request', replyTime: '2 hr', bookings: 11 }
    ],
    // One booking per StatusPill state. Data mirrors what the artboards already show.
    bookings: [
      { id: '4833', status: 'waiting_provider', listing: 'boat-1', service: 'Sunset Fishing Charter', when: 'Wed 2 Sep · 06:30 departure', amount: 'MVR 3200', amountLabel: 'Listed price' },
      { id: '4790', status: 'quote_received', listing: 'plumb-1', service: 'Emergency Plumbing & Pipe Repair', when: 'Tue 25 Aug · 14:00', amount: 'MVR 650', amountLabel: 'Quoted price' },
      { id: '4791', status: 'awaiting_payment', listing: 'plumb-1', service: 'Emergency Plumbing & Pipe Repair', when: 'Tue 25 Aug · 14:00', amount: 'MVR 650', amountLabel: 'Quoted price' },
      { id: '4792', status: 'payment_sent', listing: 'plumb-1', service: 'Emergency Plumbing & Pipe Repair', when: 'Tue 25 Aug · 14:00', amount: 'MVR 650', amountLabel: 'Quoted price' },
      { id: '4793', status: 'receipt_confirmed', listing: 'plumb-1', service: 'Emergency Plumbing & Pipe Repair', when: 'Tue 25 Aug · 14:00', amount: 'MVR 650', amountLabel: 'Quoted price' },
      { id: '4812', status: 'confirmed', listing: 'clean-1', service: 'Home Deep Cleaning', when: 'Thu 27 Aug · 11:00', amount: 'MVR 450', amountLabel: 'Agreed price' },
      { id: '4700', status: 'completed', listing: 'clean-1', service: 'Home Deep Cleaning', when: 'Tue 18 Aug · 14:00', amount: 'MVR 600', amountLabel: 'Agreed price' },
      { id: '4655', status: 'declined', listing: 'plumb-2', service: 'Bathroom & Kitchen Plumbing Installation', when: '—', amount: 'MVR 900', amountLabel: 'Listed price' },
      { id: '4610', status: 'cancelled', listing: 'clean-1', service: 'Home Deep Cleaning', when: 'Sat 8 Aug · 14:00', amount: 'MVR 450', amountLabel: 'Agreed price' },
      { id: '4590', status: 'disputed', listing: 'plumb-1', service: 'Emergency Plumbing & Pipe Repair', when: 'Tue 25 Aug · 14:00', amount: 'MVR 650', amountLabel: 'Quoted price' },
      { id: '4501', status: 'unresolved', listing: 'plumb-1', service: 'Emergency Plumbing & Pipe Repair', when: 'Mon 13 Jul · 10:00', amount: 'MVR 480', amountLabel: 'Quoted price' },
      { id: '4839', status: 'pending_offline', listing: 'clean-1', service: 'Home Deep Cleaning', when: 'Fri 4 Sep · 09:00', amount: 'MVR 450', amountLabel: 'Listed price' }
    ],
    emergencyBooking: {
      id: 'RP-4471-EMG', category: 'Plumbing', service: 'Emergency plumbing call-out',
      status: 'confirmed', calloutFee: 'MVR 350', dispatchFee: 'MVR 200', dispatchFeeOwed: true,
      windowMin: 30,
      // Each offer carries the provider's own callout fee and own ETA — an estimate, never a guarantee.
      offers: [
        { provider: 'Ibrahim Rasheed', tier: 'Gold', fee: 350, etaMin: 25 },
        { provider: 'Naseem Ali', tier: 'Gold', fee: 300, etaMin: 40 },
        { provider: 'AquaFix Maldives', tier: 'Gold', fee: 420, etaMin: 20 }
      ]
    },
    threads: [
      { booking: '4812', with: 'Mariyam Shifa' },
      { booking: '4791', with: 'Ibrahim Rasheed' },
      { booking: '4792', with: 'Ibrahim Rasheed' },
      { booking: '4700', with: 'Mariyam Shifa', locked: true },
      { booking: '4833', with: 'Ahmed Faisal' },
      { booking: 'RP-4471-EMG', with: 'Ibrahim Rasheed' },
      { enquiry: true, with: 'Ibrahim Rasheed', listing: 'plumb-1' }
    ],
    subscription: {
      plan: 'Premium', status: 'premium', nextPayment: '12 Sep',
      invoices: [
        { date: '12 Aug 2026', period: '13 Aug – 11 Sep', ref: 'RP-2026-0798', amount: 'MVR 75' },
        { date: '13 Jul 2026', period: '14 Jul – 12 Aug', ref: 'RP-2026-0651', amount: 'MVR 75' },
        { date: '13 Jun 2026', period: '14 Jun – 13 Jul', ref: 'RP-2026-0512', amount: 'MVR 75' },
        { date: '14 May 2026', period: '15 May – 13 Jun', ref: 'RP-2026-0398', amount: 'MVR 75' }
      ],
      // one payment submission awaiting confirmation (manual bank transfer, admin confirms within 48h)
      pendingPayment: { submitted: '1 Sep 2026', amount: 'MVR 75', method: 'Bank transfer', state: 'awaiting_confirmation' }
    }
  };

  window.RPSession = {
    seed: seed,
    role: function () { return load().role === 'provider' ? 'provider' : 'customer'; },
    setRole: function (r) { var s = load(); s.role = r === 'provider' ? 'provider' : 'customer'; save(s); },
    persona: function () { return this.role() === 'provider' ? seed.personas.provider : seed.personas.customer; },
    get: function (k, fallback) { var s = load(); return s.state && (k in s.state) ? s.state[k] : fallback; },
    set: function (k, v) { var s = load(); s.state = s.state || {}; s.state[k] = v; save(s); },
    reset: function () { try { localStorage.removeItem(KEY); } catch (e) {} }
  };
})();
