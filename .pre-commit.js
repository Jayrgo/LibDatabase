const fs = require("fs");
const path = require("path");

exports.preCommit = (props) => {
  const replace = (path, searchValue, replaceValue) => {
    fs.writeFileSync(path, fs.readFileSync(path, "utf-8").replace(searchValue, replaceValue));
  };

  const replaceAll = (startPath, filter, searchValue, replaceValue) => {
    // thanks: https://stackoverflow.com/questions/25460574/find-files-by-extension-html-under-a-folder-in-nodejs/25462405#25462405
    if (!fs.existsSync(startPath)) return;

    const files = fs.readdirSync(startPath);
    for (var i = 0; i < files.length; i++) {
      const filename = path.join(startPath, files[i]);
      const stat = fs.lstatSync(filename);
      if (stat.isDirectory()) {
        replaceAll(filename, filter, searchValue, replaceValue); //recurse
      } else if (filename.indexOf(filter) >= 0) {
        replace(filename, searchValue, replaceValue);
      }
    }
  };

  replaceAll("./", ".toc", /(?<=## Version: ).+/g, props.version);
  replaceAll("./", ".lua", /(?<=local _VERSION = ").+(?=")/g, props.version);
};
