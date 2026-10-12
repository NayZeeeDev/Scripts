<?php
// Renders every page with Twig's sandbox enforcing the Tebex whitelist (the filters/functions/tags Carbide's live template uses).
require 'vendor/autoload.php';
$dir = $argv[1] ?? '/home/user/Scripts/nayzeee-tebex-template/';
$cms = is_file($dir.'cms/page.html') ? 'cms/page.html' : 'cms-page.html';
$data = json_decode(file_get_contents('../twigtest/ctx.json'), true); $cfg = $data['config'];
$twig = new \Twig\Environment(new \Twig\Loader\FilesystemLoader($dir), ['strict_variables' => false]);
$policy = new \Twig\Sandbox\SecurityPolicy(
  ['if', 'for', 'set', 'include', 'extends', 'block'],
  ['replace', 'lower', 'raw', 'number_format', 'length', 'slice', 'split', 'upper', 'e', 'escape'],
  [], [], ['config', 'url']);
$twig->addExtension(new \Twig\Extension\SandboxExtension($policy, true));
$twig->addFunction(new \Twig\TwigFunction('config', fn($k) => $cfg[$k] ?? ''));
$twig->addFunction(new \Twig\TwigFunction('url', fn($a = null) => 'https://store.example/x'));
@mkdir('out_sb'); $bad = 0;
// compile-time check of every file (catches filters in branches the mock data never reaches)
foreach (array_merge(glob($dir.'*.html'), glob($dir.'*/*.html'), glob($dir.'*.twig')) as $f) {
  $name = substr($f, strlen($dir));
  try { $twig->parse($twig->tokenize(new \Twig\Source(file_get_contents($f), $name))); }
  catch (\Throwable $e) { $bad++; echo "PARSE FAIL $name: ".$e->getMessage()."\n"; }
}
foreach ($data['pages'] as $p) {
  $file = $p['file'] === 'cms-page.html' ? $cms : $p['file'];
  try { $html = $twig->render($file, $p['ctx']); file_put_contents('out_sb/'.$p['name'].'.html', $html); echo "OK   {$p['name']} ".strlen($html)."\n"; }
  catch (\Throwable $e) { $bad++; echo "FAIL {$p['name']}: ".$e->getMessage()."\n"; }
}
echo $bad ? "SANDBOX: $bad problem(s)\n" : "SANDBOX: clean\n"; exit($bad ? 1 : 0);
