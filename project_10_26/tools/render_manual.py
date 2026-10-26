"""Use the packaged DOCX renderer; native Word supplies PDF if soffice is absent."""
from pathlib import Path
import importlib.util,subprocess,os,sys
root=Path(__file__).resolve().parent.parent
skill=Path(r'C:\Users\14298\.codex\plugins\cache\openai-primary-runtime\documents\26.1024.11018\skills\documents\render_docx.py')
spec=importlib.util.spec_from_file_location('render_docx',skill);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
poppler=Path(r'C:\Users\14298\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\poppler\Library\bin')
os.environ['PATH']=str(poppler)+os.pathsep+os.environ.get('PATH','')
try:module._resolve_soffice()
except FileNotFoundError as e:
 print('Packaged renderer diagnosis:',e,flush=True)
 print('Using installed Microsoft Word for DOCX-to-PDF; packaged renderer still handles PDF-to-PNG.',flush=True)
 def word_convert(doc_path,user_profile,convert_tmp_dir,stem,verbose):
  pdf=Path(convert_tmp_dir)/(stem+'.pdf')
  p=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(root/'tools/word_to_pdf.ps1'),'-InputDoc',doc_path,'-OutputPdf',str(pdf)],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
  if p.returncode or not pdf.exists():raise RuntimeError(p.stdout+p.stderr)
  return str(pdf),p.stdout+p.stderr
 module.convert_to_pdf=word_convert
sys.argv=[str(skill),str(root/'00_Docs/随行视听西湖工程上手与复现教程.docx'),'--output_dir',str(root/'00_Docs/_qa_manual'),'--dpi','110','--emit_pdf']
module.main()
