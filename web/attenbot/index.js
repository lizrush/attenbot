var config = require('config');
var elasticsearch = require('elasticsearch');
var AgentKeepAlive = require('agentkeepalive');
var express = require('express');
var sprintf = require("sprintf-js").sprintf;
var bodyParser = require('body-parser');
var OAuth = require('oauth');
var exphbs  = require('express-handlebars');

var OAuth2 = OAuth.OAuth2;
var oauth2 = new OAuth2(config.slack.client_id,
  config.slack.client_secret,
  'https://slack.com/',
  '/oauth/authorize',
  '/api/oauth.access',
  null);

var client = new elasticsearch.Client({
  host: config.elasticsearch.host,
  sniffOnStart: true,
  maxSockets: 10,
  log: 'error',
  createNodeAgent: function (connection, config) {
    return new AgentKeepAlive(connection.makeAgentConfig(config));
  }
});

var app = express();

app.engine('handlebars', exphbs({
  defaultLayout: 'main',
  extname: 'handlebars'
}));

app.set('view engine', 'handlebars');

app.enable('view cache');

app.use(express.static('static'));

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

app.get('/', function (req, res) {
  res.render('home');
});

app.get('/complete', function (req, res) {
  res.render('complete', {complete: true});
});

app.get('/oauth', function (req, res) {

  oauth2.getOAuthAccessToken(
    req.query.code,
    {'grant_type':'client_credentials'},
    function (e, access_token, refresh_token, results) {
      res.redirect('/complete');
    }
    );
});

app.post('/search', function (req, res) {

  if (!(req.body && typeof req.body.text !== 'undefined')) {

    return res.status(400).json({
      ok: false,
      error: "query_missing"
    });
  }

  var searchQuery = req.body.text;

  client.search({
    index: config.elasticsearch.index,
    body: {
      query: {
        "bool": {
          "must": {
            match: {
              content: searchQuery
            },
          }
        }
      }
    },
    size: 5
  }, function (error, response) {

    if (error) {

      return res.json({
        "response_type": "ephemeral",
        "attachments": [{
          "text": 'Whoops, there was an error searching for ' + searchQuery,
        }]
      });
    }

    if (response && response.hits && response.hits.hits) {

      var clips = [];

      response.hits.hits.forEach(function(hit) {

        var url = config.imageBaseUrl + hit._source.filename

        var clip = {
          show: hit._source.show,
          episode: hit._source.episode,
          url: url,
        };

        clips.push(clip);
      });

      if (clips.length === 0) {
        return res.json({
          "response_type": "ephemeral",
          "attachments": [{
            "text": 'Could not match ' + searchQuery,
          }]
        });
      }

      var clip = clips[Math.floor(Math.random() * (clips.length))];

      res.json({
        "response_type": "in_channel",
        "attachments": [
          {
            "text": "Show: " + clip.show + ", " + "Episode: " + clip.episode,
            "image_url": clip.url,
            "fallback": "Whoops, something went wrong trying to fetch the gif. Try again!"
          }
        ]
      });
    } else {
      res.json({
        "response_type": "ephemeral",
        "attachments": [{
          "text": 'Could not match ' + searchQuery,
        }]
      });
    }
  });
});

client.ping({
  requestTimeout: 30000,
}, function (error) {

  if (error) {
    console.error('Elasticsearch is not available at ' + config.elasticsearch.host);
    process.exit(1);
    return;
  }

  app.listen(config.port, function () {
    console.log('Server started on port ' + config.port + '.');
  });
});
