const mdns = require('multicast-dns')();

mdns.on('query', function(query) {
  console.log('got a query packet: ', query)
});
mdns.on('response', function(response) {
  console.log('got a response packet: ', response)
});

mdns.query({
  questions:[{
    name: 'slzb-06m.local',
    type: 'A'
  }]
});
mdns.query({
  questions:[{
    name: '_slzb-06._tcp.local',
    type: 'PTR'
  }]
});

const { Bonjour: BonjourService } = require("bonjour-service");

const bj = new BonjourService();
bj.findOne({ type: 'slzb-06' }, 5000, function (service) {
  console.log('found a server: ', JSON.stringify(service));
});
