var gulp = require('gulp');
var minifycss = require('gulp-minify-css');
// var uglify = require('gulp-uglify');
var htmlmin = require('gulp-htmlmin');
var htmlclean = require('gulp-htmlclean');

// css
function miniCSS() {
    return gulp.src('./public/**/*.css')
        .pipe(minifycss())
        .pipe(gulp.dest('./public'));
}

// html
function miniHTML() {
  return gulp.src('./public/**/*.html')
    .pipe(htmlclean())
    .pipe(htmlmin({
        removeComments: true,
        minifyJS: true,
        minifyCSS: true,
        minifyURLs: true,
    }))
    .pipe(gulp.dest('./public'));
}

// js
function miniJS() {
    return gulp.src('./public/**/*.js')
        .pipe(uglify())
        .pipe(gulp.dest('./public'));
}

exports.miniHTML = miniHTML;
exports.miniCSS = miniCSS;
exports.miniJS = miniJS;

// execute gulp task
// gulp.task('default', gulp.series(miniHTML, miniCSS, miniJS));
// gulp.task('default', gulp.parallel(miniHTML, miniCSS, miniJS));

gulp.task('default', gulp.parallel(miniHTML, miniCSS));