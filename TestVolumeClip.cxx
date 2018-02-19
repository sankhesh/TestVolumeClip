#include <vtkActor.h>
#include <vtkCamera.h>
#include <vtkColorTransferFunction.h>
#include <vtkDataSetReader.h>
#include <vtkGPUVolumeRayCastMapper.h>
#include <vtkImageData.h>
#include <vtkNew.h>
#include <vtkPiecewiseFunction.h>
#include <vtkPlane.h>
#include <vtkPlaneCollection.h>
#include <vtkRenderWindow.h>
#include <vtkRenderWindowInteractor.h>
#include <vtkRenderer.h>
#include <vtkVolume.h>
#include <vtkVolumeProperty.h>

int main(int argc, char* argv[])
{
  if (argc < 2)
  {
    std::cerr << "Usage: " << argv[0] << " <input nrrd file>" << std::endl;
    return EXIT_FAILURE;
  }

  vtkNew<vtkDataSetReader> reader;
  reader->SetFileName(argv[1]);
  reader->Update();

  vtkNew<vtkGPUVolumeRayCastMapper> mapper;
  mapper->SetInputConnection(reader->GetOutputPort());
  mapper->SetUseJittering(1);

  vtkNew<vtkColorTransferFunction> ctf;
  ctf->AddRGBPoint(-2048, 0.0, 0.0, 0.0);
  ctf->AddRGBPoint(-451, 0.0, 0.0, 0.0);
  ctf->AddRGBPoint(-450, 0.1, 0.1, 0.1);
  ctf->AddRGBPoint(1050, 1.0, 1.0, 1.0);
  ctf->AddRGBPoint(3661, 1.0, 1.0, 1.0);

  vtkNew<vtkPiecewiseFunction> pf;
  pf->AddPoint(-2048, 0.0);
  pf->AddPoint(-451, 0.0);
  pf->AddPoint(-450, 1.0);
  pf->AddPoint(1050, 1.0);
  pf->AddPoint(3661, 1.0);

  vtkNew<vtkVolumeProperty> prop;
  prop->SetColor(ctf);
  prop->SetScalarOpacity(pf);
  prop->SetShade(1);

  vtkNew<vtkVolume> volume;
  volume->SetMapper(mapper);
  volume->SetProperty(prop);

  const double* bounds = vtkImageData::SafeDownCast(reader->GetOutput())->GetBounds();
  vtkNew<vtkPlane> clipPlane1;
  clipPlane1->SetOrigin(0.0, 0.25 * (bounds[2] + bounds[3]), 0.0);
  clipPlane1->SetNormal(0.0, 1.0, 0.0);

  vtkNew<vtkPlaneCollection> clipPlaneCollection;
  clipPlaneCollection->AddItem(clipPlane1);
  mapper->SetClippingPlanes(clipPlaneCollection);
  mapper->SetCroppingRegionPlanes(bounds[0], bounds[1], 0.25 * (bounds[2] + bounds[3]),  bounds[3], bounds[4], bounds[5]);
  // mapper->SetCroppingRegionFlagsToFence();
  // mapper->SetCropping(1);

  vtkNew<vtkRenderWindow> renWin;
  renWin->SetMultiSamples(0);
  renWin->SetSize(301, 300); // Intentional NPOT size

  vtkNew<vtkRenderer> ren;
  renWin->AddRenderer(ren.GetPointer());

  vtkNew<vtkRenderWindowInteractor> iren;
  iren->SetRenderWindow(renWin.GetPointer());

  ren->AddVolume(volume);
  ren->ResetCamera();

  ren->GetActiveCamera()->Zoom(1.5);
  ren->GetActiveCamera()->Roll(70);
  ren->GetActiveCamera()->Azimuth(90);

  renWin->Render();
  iren->Start();

  return EXIT_SUCCESS;
}
