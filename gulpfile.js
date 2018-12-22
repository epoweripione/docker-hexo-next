var gulp = require('gulp');
var minifycss = require('gulp-minify-css');
// var uglify = require('gulp-uglify');
var htmlmin = require('gulp-htmlmin');
var htmlclean = require('gulp-htmlclean');

// css
gulp.task('minify-css', function() {
    return gulp.src('./public/**/*.css')
        .pipe(minifycss())
        .pipe(gulp.dest('./public'));
});

// html
gulp.task('minify-html', function() {
  return gulp.src('./public/**/*.html')
    .pipe(htmlclean())
    .pipe(htmlmin({
        removeComments: true,
        minifyJS: true,
        minifyCSS: true,
        minifyURLs: true,
    }))
    .pipe(gulp.dest('./public'))
});

// js
// gulp.task('minify-js', function() {
//     return gulp.src('./public/**/*.js')
//         .pipe(uglify())
//         .pipe(gulp.dest('./public'));
// });

// execute gulp task
// gulp.task('default', [
//     'minify-html','minify-css','minify-js'
// ]);

gulp.task('default', ['minify-html', 'minify-css']);