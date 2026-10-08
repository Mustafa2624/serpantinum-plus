.pragma library

function parseState(text) {
  if (!text)
    return [];
  try {
    const parsed = JSON.parse(String(text));
    if (!parsed || !Array.isArray(parsed.items))
      return [];
    return parsed.items.filter(function(item) {
      if (!item || typeof item.uri !== "string") return false;
      return isFileUri(item.uri) || isWebUrl(item.uri);
    }).map(function(item) {
      const uri = item.uri;
      return {
        uri: uri,
        kind: (item.kind === "link" || isWebUrl(uri)) ? "link" : "file",
        name: String(item.name || displayName(uri))
      };
    });
  } catch (error) {
    return [];
  }
}

function serialize(entries) {
  return JSON.stringify({
    version: 1,
    items: (entries || []).map(function(item) {
      return {
        uri: item.uri,
        kind: item.kind === "link" || isWebUrl(item.uri) ? "link" : "file"
      };
    })
  }, null, 2) + "\n";
}

function isWebUrl(uri) {
  return /^https?:\/\//i.test(String(uri || "").trim());
}

function isFileUri(uri) {
  return /^file:\/\//i.test(String(uri || "").trim());
}

function webUrls(urls, text, nativeUrl) {
  const result = [];

  function add(value) {
    const normalized = normalizeCandidate(value);
    const match = normalized.match(/https?:\/\/[^\s\r\n"'<>]+/i);
    if (!match) return;

    let url = match[0].replace(/[),.;]+$/, "");
    try {
      url = decodeURIComponent(url);
    } catch (error) {}

    if (isWebUrl(url) && result.indexOf(url) === -1)
      result.push(url);
  }

  for (let i = 0; i < (urls || []).length; i++)
    add(urls[i]);

  if (text)
    add(text);

  if (nativeUrl) {
    const lines = String(nativeUrl).split(/[\r\n]+/);

    for (let j = 0; j < lines.length; j++) {
      if (lines[j].trim() !== "") {
        add(lines[j]);
        break;
      }
    }
  }

  return result;
}

function looksLikeImageSource(url) {
  const value = String(url || "");

  if (isDataImageUri(value))
    return true;

  return looksLikeImageUrl(value) && !isKnownPageUrl(value);
}

function localUrls(urls) {
  const result = [];

  for (let i = 0; i < urls.length; i++) {
    const uri = String(urls[i]);

    if (uri.startsWith("file://") && result.indexOf(uri) === -1)
      result.push(uri);
  }

  return result;
}

function remoteImageCandidates(urls, text, html, nativeUrl) {
  const tiers = {
    extracted: [],
    native: [],
    html: [],
    image: [],
    page: []
  };

  function add(value, origin) {
    const candidate = normalizeCandidate(value);

    if (!candidate)
      return;

    if (isDataImageUri(candidate)) {
      tiers.html.push(candidate);
      return;
    }

    const extracted = extractGoogleImageUrl(candidate);

    if (/^https?:\/\/[^\s]+$/i.test(extracted))
      tiers.extracted.push(extracted);

    const url = firstHttpUrl(candidate, origin === "text");

    if (!url)
      return;

    if (isKnownPageUrl(url)) {
      tiers.page.push(url);
      return;
    }

    if (origin === "native")
      tiers.native.push(url);
    else if (origin === "html")
      tiers.html.push(url);
    else if (looksLikeImageUrl(url))
      tiers.image.push(url);
    else
      tiers.page.push(url);
  }

  for (let i = 0; i < (urls || []).length; i++)
    add(String(urls[i]), "urls");

  if (text)
    add(String(text), "text");

  if (html) {
    const source = String(html);

    const src = source.match(
      /<img\b[^>]*\bsrc=["']([^"']+)["']/i
    );

    if (src)
      add(src[1], "html");

    const srcset = source.match(
      /<img\b[^>]*\bsrcset=["']([^"']+)["']/i
    );

    if (srcset)
      add(srcset[1].split(/[\s,]+/)[0], "html");
  }

  if (nativeUrl) {
    const lines = String(nativeUrl).split(/[\r\n]+/);

    for (let j = 0; j < lines.length; j++) {
      if (lines[j].trim() !== "") {
        add(lines[j], "native");
        break;
      }
    }
  }

  const ordered = tiers.extracted.concat(
    tiers.native,
    tiers.html,
    tiers.image,
    tiers.page
  );

  const result = [];

  for (let k = 0; k < ordered.length; k++) {
    if (result.indexOf(ordered[k]) === -1)
      result.push(ordered[k]);
  }

  return result;
}

function normalizeCandidate(value) {
  return String(value || "")
    .trim()
    .replace(/&amp;/g, "&")
    .replace(/\\u003d/g, "=")
    .replace(/\\u0026/g, "&")
    .replace(/\\u002f/gi, "/");
}

function firstHttpUrl(value, trimPunctuation) {
  const match = String(value || "")
    .match(/https?:\/\/[^\s\r\n"'<>]+/i);

  if (!match)
    return "";

  return trimPunctuation
    ? match[0].replace(/[),.;]+$/, "")
    : match[0];
}

function isDataImageUri(value) {
  return /^data:image\/[a-z0-9.+-]+;base64,/i.test(
    String(value || "")
  );
}

function parseDataUri(value) {
  const match = String(value || "")
    .match(
      /^data:(image\/[a-z0-9.+-]+);base64,([\s\S]+)$/i
    );

  if (!match)
    return null;

  const payload = match[2]
    .replace(/%2B/gi, "+")
    .replace(/%2F/gi, "/")
    .replace(/%3D/gi, "=")
    .replace(/\s+/g, "");

  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(payload))
    return null;

  return {
    mime: match[1].toLowerCase(),
    base64: payload
  };
}

function hostOf(url) {
  const match = String(url || "")
    .match(/^https?:\/\/([^\/?#]+)/i);

  return match
    ? match[1].toLowerCase().replace(/:\d+$/, "")
    : "";
}

function looksLikeImageUrl(url) {
  const path = String(url || "").split(/[?#]/)[0];

  if (/\.(avif|bmp|gif|heic|heif|jpe?g|png|svg|webp)$/i.test(path))
    return true;

  const host = hostOf(url);

  return /^(media\d*|i|img|images|cdn)\./i.test(host)
    || /\.gstatic\.com$/i.test(host)
    || host === "i.pinimg.com";
}

function isKnownPageUrl(url) {
  const host = hostOf(url);

  const rest = String(url || "")
    .replace(/^https?:\/\/[^\/?#]+/i, "");

  if (
    /(^|\.)google\./i.test(host)
    && /^\/(imgres|search|url)([\/?#]|$)/i.test(rest)
  )
    return true;

  if (
    /(^|\.)giphy\.com$/i.test(host)
    && /^\/gifs([\/?#]|$)/i.test(rest)
  )
    return true;

  return false;
}

function refererFor(url) {
  const match = String(url || "")
    .match(/^(https?:\/\/[^\/?#]+)/i);

  return match
    ? match[1] + "/"
    : "";
}

function extractGoogleImageUrl(value) {
  const candidate = normalizeCandidate(value);

  if (!candidate)
    return "";

  const match = candidate.match(
    /(?:imgurl|mediaurl)(?:=|%3D)(https?(?:%253A|%3A|:)(?:%252F|%2F|\/){2}[^&\s"']+)/i
  );

  if (!match)
    return "";

  let decoded = match[1];

  try {
    decoded = decodeURIComponent(decoded);
  } catch (error) {
    return match[1];
  }

  if (!/^https?:\/\//i.test(decoded)) {
    try {
      const again = decodeURIComponent(decoded);

      if (/^https?:\/\//i.test(again))
        decoded = again;
    } catch (error) {}
  }

  return decoded;
}

function base64FromArrayBuffer(buffer) {
  const alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  const bytes = new Uint8Array(buffer);
  const parts = [];
  let chunk = "";

  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;

    chunk += alphabet[b0 >> 2];

    chunk += alphabet[
      ((b0 & 3) << 4) | (b1 >> 4)
    ];

    chunk += i + 1 < bytes.length
      ? alphabet[((b1 & 15) << 2) | (b2 >> 6)]
      : "=";

    chunk += i + 2 < bytes.length
      ? alphabet[b2 & 63]
      : "=";

    if (chunk.length >= 8192) {
      parts.push(chunk);
      chunk = "";
    }
  }

  parts.push(chunk);

  return parts.join("");
}

function addUrls(entries, urls) {
  const result = (entries || []).slice();
  const seen = {};

  for (let i = 0; i < result.length; i++)
    seen[result[i].uri] = true;

  for (let j = 0; j < urls.length; j++) {
    const uri = String(urls[j] || "");

    if (!uri || seen[uri])
      continue;

    result.push({
      uri: uri,
      kind: isWebUrl(uri) ? "link" : "file",
      name: displayName(uri)
    });

    seen[uri] = true;
  }

  return result;
}

function removeAt(entries, index) {
  const result = (entries || []).slice();

  if (index >= 0 && index < result.length)
    result.splice(index, 1);

  return result;
}

function removeUri(entries, uri) {
  return (entries || []).filter(function(item) {
    return item.uri !== uri;
  });
}

function displayName(uri) {
  const value = String(uri || "");

  if (isWebUrl(value)) {
    const withoutScheme = value.replace(
      /^https?:\/\//i,
      ""
    );

    const host = (
      withoutScheme.split(/[/?#]/)[0] || "Link"
    ).replace(/^www\./i, "");

    const pathPart = withoutScheme
      .replace(/^[^/?#]*/, "")
      .split(/[?#]/)[0]
      .replace(/\/+$/, "");

    const last = pathPart
      .split("/")
      .filter(function(part) {
        return part !== "";
      })
      .pop();

    if (last) {
      try {
        return host + " / " + decodeURIComponent(last);
      } catch (error) {
        return host + " / " + last;
      }
    }

    return host;
  }

  const parts = value.split("/");

  const encoded =
    parts.length > 0
      ? parts[parts.length - 1]
      : "File";

  try {
    return decodeURIComponent(encoded) || "File";
  } catch (error) {
    return encoded || "File";
  }
}

function isImage(name) {
  return /\.(avif|bmp|gif|heic|heif|jpe?g|png|svg|webp)$/i.test(
    String(name)
  );
}
